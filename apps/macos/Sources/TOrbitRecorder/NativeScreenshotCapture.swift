import Foundation
import TOrbitRecorderCore

enum NativeScreenshotError: Error, Equatable, CustomStringConvertible {
    case cancelled
    case failed(Int32)
    case emptyOutput

    var description: String {
        switch self {
        case .cancelled:
            return "Screenshot cancelled"
        case .failed(let status):
            return "Screenshot capture failed with status \(status)"
        case .emptyOutput:
            return "Screenshot output is empty"
        }
    }
}

enum NativeScreenshotCapture {
    static func captureFullScreen(sessionFolderURL: URL) async throws -> URL {
        let outputURL = RecordingDerivedArtifactPaths.screenshotURL(sessionFolderURL: sessionFolderURL)
        return try await Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(
                at: outputURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            let process = Process()
            process.executableURL = URL(fileURLWithPath: ScreenshotCaptureCommand.executablePath)
            process.arguments = ScreenshotCaptureCommand.fullScreenArguments(
                outputPath: outputURL.path(percentEncoded: false)
            )
            try process.run()
            process.waitUntilExit()

            guard process.terminationStatus == 0 else {
                throw NativeScreenshotError.failed(process.terminationStatus)
            }

            guard let size = try? FileManager.default
                .attributesOfItem(atPath: outputURL.path(percentEncoded: false))[.size] as? NSNumber,
                  size.int64Value > 0
            else {
                throw NativeScreenshotError.emptyOutput
            }

            AppLogger.file(.info, category: "library", "screenshot captured path=\(outputURL.path(percentEncoded: false))")
            return outputURL
        }.value
    }
}
