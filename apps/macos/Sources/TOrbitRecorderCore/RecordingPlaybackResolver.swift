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
