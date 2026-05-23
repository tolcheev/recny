import Foundation
import TOrbitRecorderCore

@main
enum TOrbitRecorderSystemAudioSmokeTest {
    static func main() async {
        do {
            let arguments = CommandLine.arguments
            let duration = TimeInterval(value(after: "--duration", in: arguments) ?? "10") ?? 10
            let root = URL(fileURLWithPath: value(after: "--root", in: arguments) ?? "/tmp/TOrbitRecorderSystemAudioSmokeTest")
            let sourceURL = root.appendingPathComponent("source", isDirectory: true)
            let outputURL = sourceURL.appendingPathComponent("system.m4a")

            try FileManager.default.removeItemIfExists(at: root)
            try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)

            let recorder = ScreenCaptureKitSystemAudioRecorder()
            try await recorder.start(outputURL: outputURL)
            try await Task.sleep(for: .milliseconds(Int(max(0, duration) * 1_000)))
            let result = try await recorder.stop()

            let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path(percentEncoded: false))
            let size = (attributes[.size] as? NSNumber)?.int64Value ?? 0
            guard size > 0 else {
                throw RecordingControllerError.systemAudioWriteFailed("Empty file at \(outputURL.path(percentEncoded: false))")
            }

            print("system_audio_smoke_test=passed")
            print("system_audio_file=\(outputURL.path(percentEncoded: false))")
            print("file_size=\(size)")
            print("sample_count=\(result.sampleCount)")
            print("duration_sec=\(String(format: "%.2f", result.duration))")
        } catch {
            fputs("system_audio_smoke_test=failed\n", stderr)
            fputs("error=\(String(describing: error))\n", stderr)
            exit(2)
        }
    }

    private static func value(after flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag) else {
            return nil
        }

        let valueIndex = arguments.index(after: index)
        guard valueIndex < arguments.endIndex else {
            return nil
        }

        return arguments[valueIndex]
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        if fileExists(atPath: path) {
            try removeItem(at: url)
        }
    }
}
