import Foundation

public enum ScreenshotCaptureCommand {
    public static let executablePath = "/usr/sbin/screencapture"

    public static func fullScreenArguments(outputPath: String) -> [String] {
        ["-x", outputPath]
    }
}
