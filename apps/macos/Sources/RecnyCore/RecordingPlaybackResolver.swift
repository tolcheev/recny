import Foundation

public enum RecordingPlaybackKind: String, Equatable, Sendable {
    case balanced
    case original
    case microphone
    case system

    public var displayName: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .original:
            return "Original"
        case .microphone:
            return "Mic only"
        case .system:
            return "System only"
        }
    }
}

public struct RecordingPlaybackCandidate: Equatable, Sendable {
    public let kind: RecordingPlaybackKind
    public let url: URL
    public let fileSizeBytes: Int64

    public init(kind: RecordingPlaybackKind, url: URL, fileSizeBytes: Int64) {
        self.kind = kind
        self.url = url
        self.fileSizeBytes = fileSizeBytes
    }
}

public struct RecordingInlinePlaybackRequest: Equatable, Identifiable, Sendable {
    public let recordingID: String
    public let url: URL
    public let title: String
    public let kind: RecordingPlaybackKind

    public var id: String {
        "\(recordingID)|\(url.path(percentEncoded: false))"
    }

    public init(
        recordingID: String,
        recordingTitle: String,
        candidate: RecordingPlaybackCandidate
    ) {
        self.recordingID = recordingID
        self.url = candidate.url
        self.kind = candidate.kind
        let trimmedTitle = recordingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseTitle = trimmedTitle.isEmpty ? "Untitled recording" : trimmedTitle
        self.title = "\(baseTitle) - \(candidate.kind.displayName)"
    }
}

public enum RecordingPlaybackDisplayState: Equatable, Sendable {
    case balancedReady
    case originalOnly
    case balancedFailed
    case levelingSkipped
    case fallbackSource(RecordingPlaybackKind)
    case missing
}

public enum RecordingPlaybackResolver {
    public static func shouldStopPlaybackBeforeDeleting(
        inlinePlayback: RecordingInlinePlaybackRequest?,
        deletedRecordingID: String,
        deletedSessionFolderURL: URL
    ) -> Bool {
        guard let inlinePlayback else {
            return false
        }

        return inlinePlayback.recordingID == deletedRecordingID
            || isPlaybackURL(inlinePlayback.url, insideSessionFolder: deletedSessionFolderURL)
    }

    public static func isPlaybackURL(
        _ playbackURL: URL?,
        insideSessionFolder sessionFolderURL: URL
    ) -> Bool {
        guard let playbackURL else {
            return false
        }

        let playbackPath = normalizedPath(playbackURL)
        let sessionPath = normalizedDirectoryPath(sessionFolderURL)
        return playbackPath.hasPrefix(sessionPath)
    }

    public static func preferredPlayback(
        sessionFolderURL: URL,
        processingStatus: BalancedMixStatus = .skipped
    ) -> RecordingPlaybackCandidate? {
        playbackCandidates(sessionFolderURL: sessionFolderURL, processingStatus: processingStatus).first
    }

    public static func preferredShareableAudio(
        sessionFolderURL: URL
    ) -> RecordingPlaybackCandidate? {
        playbackCandidates(sessionFolderURL: sessionFolderURL).first
    }

    public static func preferredUserFacingShareableAudio(
        for recording: RecordingSummary
    ) throws -> RecordingPlaybackCandidate? {
        guard let source = preferredShareableAudio(sessionFolderURL: recording.sessionFolderURL) else {
            return nil
        }

        let shareDirectory = recording.sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("share", isDirectory: true)
        try FileManager.default.createDirectory(
            at: shareDirectory,
            withIntermediateDirectories: true
        )

        let fileExtension = source.url.pathExtension.isEmpty ? "m4a" : source.url.pathExtension
        let destination = shareDirectory.appendingPathComponent(
            "\(shareFileStem(for: recording, kind: source.kind)).\(fileExtension)"
        )

        if normalizedPath(source.url) != normalizedPath(destination),
           shouldRefreshShareCopy(sourceURL: source.url, destinationURL: destination) {
            if FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: source.url, to: destination)
        }

        guard let size = nonEmptyFileSize(at: destination) else {
            return source
        }

        return RecordingPlaybackCandidate(kind: source.kind, url: destination, fileSizeBytes: size)
    }

    public static func playbackCandidates(
        sessionFolderURL: URL,
        processingStatus: BalancedMixStatus = .skipped
    ) -> [RecordingPlaybackCandidate] {
        let balancedURL = balancedMixedURL(sessionFolderURL: sessionFolderURL)
        let originalURL = originalMixedURL(sessionFolderURL: sessionFolderURL)
        let microphoneURL = sessionFolderURL.appendingPathComponent("source/mic.m4a")
        let systemURL = sessionFolderURL.appendingPathComponent("source/system.m4a")

        return [
            nonEmptyCandidate(kind: .balanced, url: balancedURL),
            nonEmptyCandidate(kind: .original, url: originalURL),
            nonEmptyCandidate(kind: .microphone, url: microphoneURL),
            nonEmptyCandidate(kind: .system, url: systemURL)
        ].compactMap { $0 }
    }

    public static func displayState(
        sessionFolderURL: URL,
        processingStatus: BalancedMixStatus
    ) -> RecordingPlaybackDisplayState {
        if nonEmptyFileSize(at: balancedMixedURL(sessionFolderURL: sessionFolderURL)) != nil {
            return .balancedReady
        }

        if nonEmptyFileSize(at: originalMixedURL(sessionFolderURL: sessionFolderURL)) != nil {
            switch processingStatus {
            case .failed:
                return .balancedFailed
            case .skipped:
                return .levelingSkipped
            case .done, .partial:
                return .originalOnly
            }
        }

        if processingStatus == .failed,
           (
            nonEmptyFileSize(at: sessionFolderURL.appendingPathComponent("source/mic.m4a")) != nil
                || nonEmptyFileSize(at: sessionFolderURL.appendingPathComponent("source/system.m4a")) != nil
           ) {
            return .balancedFailed
        }

        if nonEmptyFileSize(at: sessionFolderURL.appendingPathComponent("source/mic.m4a")) != nil {
            return .fallbackSource(.microphone)
        }

        if nonEmptyFileSize(at: sessionFolderURL.appendingPathComponent("source/system.m4a")) != nil {
            return .fallbackSource(.system)
        }

        return .missing
    }

    public static func originalMixedURL(sessionFolderURL: URL) -> URL {
        sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("mixed.m4a")
    }

    public static func balancedMixedURL(sessionFolderURL: URL) -> URL {
        sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("mixed_balanced.m4a")
    }

    public static func audioAnalysisURL(sessionFolderURL: URL) -> URL {
        sessionFolderURL
            .appendingPathComponent("analysis", isDirectory: true)
            .appendingPathComponent("audio_analysis.json")
    }

    public static func nonEmptyFileSize(at url: URL) -> Int64? {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path),
              let size = try? FileManager.default.attributesOfItem(atPath: path)[.size] as? NSNumber,
              size.int64Value > 0
        else {
            return nil
        }

        return size.int64Value
    }

    private static func nonEmptyCandidate(
        kind: RecordingPlaybackKind,
        url: URL
    ) -> RecordingPlaybackCandidate? {
        guard let size = nonEmptyFileSize(at: url) else {
            return nil
        }

        return RecordingPlaybackCandidate(kind: kind, url: url, fileSizeBytes: size)
    }

    private static func shouldRefreshShareCopy(sourceURL: URL, destinationURL: URL) -> Bool {
        let destinationPath = destinationURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: destinationPath) else {
            return true
        }

        let sourcePath = sourceURL.path(percentEncoded: false)
        guard
            let sourceAttributes = try? FileManager.default.attributesOfItem(atPath: sourcePath),
            let destinationAttributes = try? FileManager.default.attributesOfItem(atPath: destinationPath)
        else {
            return true
        }

        let sourceSize = (sourceAttributes[.size] as? NSNumber)?.int64Value
        let destinationSize = (destinationAttributes[.size] as? NSNumber)?.int64Value
        guard sourceSize == destinationSize else {
            return true
        }

        guard
            let sourceModifiedAt = sourceAttributes[.modificationDate] as? Date,
            let destinationModifiedAt = destinationAttributes[.modificationDate] as? Date
        else {
            return false
        }

        return sourceModifiedAt > destinationModifiedAt
    }

    private static func shareFileStem(
        for recording: RecordingSummary,
        kind: RecordingPlaybackKind
    ) -> String {
        var parts = [
            titleFileToken(recording.title),
            dateFileToken(from: recording.startedAt)
        ].filter { !$0.isEmpty }

        if parts.isEmpty {
            parts = [sanitizedFileToken(recording.id)]
        }

        if parts.isEmpty {
            parts = ["recording"]
        }

        if kind == .microphone || kind == .system {
            parts.append(kindFileSuffix(kind))
        }

        let stem = parts.joined(separator: "_")
        return String(stem.prefix(180)).trimmingCharacters(in: CharacterSet(charactersIn: "_-. "))
    }

    private static func titleFileToken(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.localizedCaseInsensitiveCompare("Untitled recording") != .orderedSame
        else {
            return "recording"
        }

        return sanitizedFileToken(trimmed)
    }

    private static func dateFileToken(from startedAt: String) -> String {
        let normalized = startedAt.trimmingCharacters(in: .whitespacesAndNewlines)
        let dateToken = normalized
            .split(whereSeparator: { $0 == "T" || $0.isWhitespace })
            .first
            .map(String.init) ?? normalized

        let dateParts = dateToken
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "/", with: "-")
            .split(separator: "-")
            .map(String.init)

        guard dateParts.count == 3 else {
            return ""
        }

        let year = dateParts[0]
        let month = paddedDatePart(dateParts[1])
        let day = paddedDatePart(dateParts[2])
        guard year.count >= 2,
              !month.isEmpty,
              !day.isEmpty
        else {
            return ""
        }

        return "\(day)_\(month)_\(year.suffix(2))"
    }

    private static func paddedDatePart(_ value: String) -> String {
        guard let integer = Int(value) else {
            return ""
        }

        return String(format: "%02d", integer)
    }

    private static func kindFileSuffix(_ kind: RecordingPlaybackKind) -> String {
        switch kind {
        case .balanced:
            return "balanced"
        case .original:
            return "original"
        case .microphone:
            return "mic_only"
        case .system:
            return "system_only"
        }
    }

    private static func sanitizedFileToken(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_@#")

        let scalars = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .unicodeScalars
        var result = ""
        var lastWasSeparator = false

        for scalar in scalars {
            if allowed.contains(scalar) {
                result.unicodeScalars.append(scalar)
                lastWasSeparator = false
            } else if !lastWasSeparator {
                result.append("_")
                lastWasSeparator = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_-. "))
    }

    private static func normalizedDirectoryPath(_ url: URL) -> String {
        let path = normalizedPath(url)
        return path.hasSuffix("/") ? path : "\(path)/"
    }

    private static func normalizedPath(_ url: URL) -> String {
        url.standardizedFileURL
            .resolvingSymlinksInPath()
            .path(percentEncoded: false)
    }
}
