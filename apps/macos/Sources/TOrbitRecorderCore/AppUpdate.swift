import Foundation

public enum AppUpdatePlatform: String, Codable, Equatable, Sendable {
    case macOS = "macos"
    case windows
}

public struct AppUpdateManifest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let generatedAt: String?
    public let macOS: AppUpdateRelease
    public let windows: AppUpdateRelease

    public init(
        schemaVersion: Int,
        generatedAt: String?,
        macOS: AppUpdateRelease,
        windows: AppUpdateRelease
    ) {
        self.schemaVersion = schemaVersion
        self.generatedAt = generatedAt
        self.macOS = macOS
        self.windows = windows
    }

    public func release(for platform: AppUpdatePlatform) -> AppUpdateRelease {
        switch platform {
        case .macOS:
            return macOS
        case .windows:
            return windows
        }
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case generatedAt = "generated_at"
        case macOS = "macos"
        case windows
    }
}

public struct AppUpdateRelease: Codable, Equatable, Sendable {
    public let version: String
    public let displayVersion: String
    public let build: String?
    public let releaseURL: URL
    public let downloadURL: URL
    public let sha256URL: URL?
    public let notes: String?

    public init(
        version: String,
        displayVersion: String,
        build: String?,
        releaseURL: URL,
        downloadURL: URL,
        sha256URL: URL?,
        notes: String?
    ) {
        self.version = version
        self.displayVersion = displayVersion
        self.build = build
        self.releaseURL = releaseURL
        self.downloadURL = downloadURL
        self.sha256URL = sha256URL
        self.notes = notes
    }

    enum CodingKeys: String, CodingKey {
        case version
        case displayVersion = "display_version"
        case build
        case releaseURL = "release_url"
        case downloadURL = "download_url"
        case sha256URL = "sha256_url"
        case notes
    }
}

public struct AppVersion: Comparable, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prerelease: String?

    public init(_ rawValue: String) {
        let trimmed = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = trimmed.hasPrefix("v")
            ? String(trimmed.dropFirst())
            : trimmed
        let versionAndSuffix = withoutPrefix.split(separator: "-", maxSplits: 1).map(String.init)
        let numberParts = versionAndSuffix.first?
            .split(separator: ".")
            .compactMap { Int($0) } ?? []

        self.major = numberParts.indices.contains(0) ? numberParts[0] : 0
        self.minor = numberParts.indices.contains(1) ? numberParts[1] : 0
        self.patch = numberParts.indices.contains(2) ? numberParts[2] : 0
        self.prerelease = versionAndSuffix.indices.contains(1) ? versionAndSuffix[1] : nil
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        if lhs.major != rhs.major {
            return lhs.major < rhs.major
        }
        if lhs.minor != rhs.minor {
            return lhs.minor < rhs.minor
        }
        if lhs.patch != rhs.patch {
            return lhs.patch < rhs.patch
        }

        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil):
            return false
        case (nil, _?):
            return false
        case (_?, nil):
            return true
        case let (left?, right?):
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }
}

public struct AppUpdateCheckResult: Equatable, Sendable {
    public let currentVersion: String
    public let latestRelease: AppUpdateRelease

    public var isUpdateAvailable: Bool {
        AppVersion(currentVersion) < AppVersion(latestRelease.version)
    }

    public var displayText: String {
        if isUpdateAvailable {
            return "Update available: \(latestRelease.displayVersion)"
        }

        return "You are on the latest version: \(latestRelease.displayVersion)"
    }
}

public final class AppUpdateChecker: @unchecked Sendable {
    public static let defaultManifestURL = URL(
        string: "https://raw.githubusercontent.com/tolcheev/torec-releases/main/latest.json"
    )!

    private let manifestURL: URL
    private let session: URLSession
    private let decoder: JSONDecoder

    public init(
        manifestURL: URL = AppUpdateChecker.defaultManifestURL,
        session: URLSession = .shared,
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.manifestURL = manifestURL
        self.session = session
        self.decoder = decoder
    }

    public func check(
        platform: AppUpdatePlatform,
        currentVersion: String
    ) async throws -> AppUpdateCheckResult {
        let (data, response) = try await session.data(from: manifestURL)
        if let httpResponse = response as? HTTPURLResponse,
           !(200..<300).contains(httpResponse.statusCode) {
            throw AppUpdateError.badStatus(httpResponse.statusCode)
        }

        let manifest = try Self.decodeManifest(data, decoder: decoder)
        return AppUpdateCheckResult(
            currentVersion: currentVersion,
            latestRelease: manifest.release(for: platform)
        )
    }

    public static func decodeManifest(
        _ data: Data,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> AppUpdateManifest {
        let manifest = try decoder.decode(AppUpdateManifest.self, from: data)
        guard manifest.schemaVersion == 1 else {
            throw AppUpdateError.unsupportedSchema(manifest.schemaVersion)
        }
        return manifest
    }
}

public enum AppUpdateError: Error, Equatable, CustomStringConvertible, Sendable {
    case badStatus(Int)
    case unsupportedSchema(Int)

    public var description: String {
        switch self {
        case .badStatus(let status):
            return "Update manifest request failed with HTTP \(status)."
        case .unsupportedSchema(let schema):
            return "Unsupported update manifest schema \(schema)."
        }
    }
}
