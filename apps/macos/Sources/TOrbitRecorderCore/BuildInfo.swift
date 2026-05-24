import Foundation

public enum BuildInfo {
    public static let fallbackAppVersion = "v0.1.0-mvp"
    public static let fallbackBuildDate = "development"
    public static let fallbackGitCommit = "unknown"

    public static var appVersion: String {
        infoValue("TORbitAppVersion") ?? fallbackAppVersion
    }

    public static var buildDate: String {
        infoValue("TORbitBuildDate") ?? fallbackBuildDate
    }

    public static var gitCommit: String {
        infoValue("TORbitGitCommit") ?? fallbackGitCommit
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
