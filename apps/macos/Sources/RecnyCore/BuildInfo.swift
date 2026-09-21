import Foundation

public enum BuildInfo {
    public static let fallbackAppVersion = "v0.1.0-mvp"
    public static let fallbackBuildDate = "development"
    public static let fallbackGitCommit = "unknown"

    public static var appVersion: String {
        infoValue("RecnyAppVersion") ?? fallbackAppVersion
    }

    public static var currentUpdateVersion: String {
        updateVersion(
            marketingVersion: infoValue("CFBundleShortVersionString"),
            displayVersion: appVersion
        )
    }

    public static func updateVersion(
        marketingVersion: String?,
        displayVersion: String
    ) -> String {
        let trimmedMarketingVersion = marketingVersion?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let trimmedMarketingVersion, !trimmedMarketingVersion.isEmpty else {
            return displayVersion
        }

        return trimmedMarketingVersion
    }

    public static var buildDate: String {
        infoValue("RecnyBuildDate") ?? fallbackBuildDate
    }

    public static var gitCommit: String {
        infoValue("RecnyGitCommit") ?? fallbackGitCommit
    }

    private static func infoValue(_ key: String) -> String? {
        guard let value = Bundle.main.infoDictionary?[key] as? String else {
            return nil
        }

        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
