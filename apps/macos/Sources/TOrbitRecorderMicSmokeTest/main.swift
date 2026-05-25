import AVFoundation
import Foundation
import TOrbitRecorderCore

@main
enum TOrbitRecorderMicSmokeTest {
    @MainActor
    static func main() async {
        let duration = parseDuration()
        let rootURL = parseRootURL()
        let authorizationStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        AppLogger.configureFileLogging(rootURL: rootURL)

        guard authorizationStatus == .authorized else {
            print("Microphone smoke test skipped.")
            print("authorization_status=\(authorizationStatus.description)")
            print("reason=The CLI process does not currently have microphone permission. Run the app manually and grant microphone access, or grant microphone access to the terminal process before re-running this smoke test.")
            Foundation.exit(2)
        }

        let controller = AVFoundationMicrophoneRecordingController()

        do {
            _ = try await controller.startRecording(outputFolder: rootURL)
            try await Task.sleep(for: .seconds(duration))
            let update = try await controller.stopRecording()

            guard let draft = update.postCallDraft else {
                throw RecordingControllerError.notRecording
            }

            let micURL = draft.sessionFolderURL
                .appendingPathComponent("source", isDirectory: true)
                .appendingPathComponent("mic.m4a")
            let attributes = try FileManager.default.attributesOfItem(
                atPath: micURL.path(percentEncoded: false)
            )
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0

            print("Microphone smoke test completed.")
            print("duration_sec=\(duration)")
            print("mic_file=\(micURL.path(percentEncoded: false))")
            print("mic_file_size=\(size)")
            print("metadata_file=\(draft.metadataURL.path(percentEncoded: false))")

            if size <= 0 {
                Foundation.exit(3)
            }
        } catch {
            print("Microphone smoke test failed.")
            print("error=\(String(describing: error))")
            Foundation.exit(1)
        }
    }

    private static func parseDuration() -> Int {
        guard let index = CommandLine.arguments.firstIndex(of: "--duration"),
              CommandLine.arguments.indices.contains(index + 1),
              let duration = Int(CommandLine.arguments[index + 1])
        else {
            return 10
        }

        return max(1, duration)
    }

    private static func parseRootURL() -> URL {
        guard let index = CommandLine.arguments.firstIndex(of: "--root"),
              CommandLine.arguments.indices.contains(index + 1)
        else {
            return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("TOrbitRecorderMicSmokeTest", isDirectory: true)
        }

        return URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
    }
}

private extension AVAuthorizationStatus {
    var description: String {
        switch self {
        case .notDetermined:
            return "not_determined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        @unknown default:
            return "unknown"
        }
    }
}
