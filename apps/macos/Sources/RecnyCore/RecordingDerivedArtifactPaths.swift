import Foundation

public enum RecordingDerivedArtifactPaths {
    public static func trimmedAudioURL(
        sessionFolderURL: URL,
        date: Date = Date()
    ) -> URL {
        sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("clip_\(timestamp(for: date)).m4a")
    }

    public static func screenshotURL(
        sessionFolderURL: URL,
        date: Date = Date()
    ) -> URL {
        sessionFolderURL
            .appendingPathComponent("screenshots", isDirectory: true)
            .appendingPathComponent("screenshot_\(timestamp(for: date)).png")
    }

    private static func timestamp(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss-SSS"
        return formatter.string(from: date)
    }
}
