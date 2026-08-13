import Foundation

public struct StoragePathBuilder: Sendable {
    public let rootURL: URL

    public init(rootURL: URL = RecordingPaths.defaultRoot) {
        self.rootURL = rootURL
    }

    public var inboxURL: URL {
        rootURL.appendingPathComponent("Inbox", isDirectory: true)
    }

    public var inboxUnsortedURL: URL {
        inboxURL.appendingPathComponent("Unsorted", isDirectory: true)
    }

    public var inboxShortURL: URL {
        inboxURL.appendingPathComponent("Short", isDirectory: true)
    }

    public var inboxFailedURL: URL {
        inboxURL.appendingPathComponent("Failed", isDirectory: true)
    }

    public var libraryURL: URL {
        rootURL.appendingPathComponent("Library", isDirectory: true)
    }

    public var dbDirectoryURL: URL {
        rootURL.appendingPathComponent("db", isDirectory: true)
    }

    public var dbURL: URL {
        dbDirectoryURL.appendingPathComponent("app.sqlite")
    }

    public var logsURL: URL {
        rootURL.appendingPathComponent("logs", isDirectory: true)
    }

    public func baseDirectories() -> [URL] {
        [
            inboxUnsortedURL,
            inboxShortURL,
            inboxFailedURL,
            libraryURL,
            dbDirectoryURL,
            logsURL
        ]
    }

    public func temporarySessionURL(id: String) -> URL {
        inboxUnsortedURL.appendingPathComponent(safePathComponent(id), isDirectory: true)
    }

    public func libraryMonthURL(startedAt: Date) -> URL {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let year = String(calendar.component(.year, from: startedAt))
        let month = String(format: "%02d", calendar.component(.month, from: startedAt))

        return libraryURL
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
    }

    public func librarySessionURL(
        startedAt: Date,
        sourceAppName: String,
        suffix: String?
    ) -> URL {
        libraryMonthURL(startedAt: startedAt)
            .appendingPathComponent(
                libraryFolderName(startedAt: startedAt, sourceAppName: sourceAppName, suffix: suffix),
                isDirectory: true
            )
    }

    public func libraryFolderName(
        startedAt: Date,
        sourceAppName: String,
        suffix: String?
    ) -> String {
        var name = "\(formatDate(startedAt, format: "yyyy-MM-dd_HH-mm"))_\(safePathComponent(sourceAppName))_audio"

        if let suffix, !suffix.isEmpty {
            name += "-\(safePathComponent(suffix))"
        }

        return name
    }

    public func safePathComponent(_ value: String) -> String {
        let lowercased = value.lowercased()
        var result = ""
        var lastWasSeparator = false

        for scalar in lowercased.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("-")
                lastWasSeparator = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return trimmed.isEmpty ? "unknown" : trimmed
    }

    public func formatDate(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = format
        return formatter.string(from: date)
    }
}
