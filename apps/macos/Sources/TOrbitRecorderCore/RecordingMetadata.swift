import Foundation

public enum TaggingStatus: String, CaseIterable, Codable, Sendable {
    case needsTagging = "needs_tagging"
    case saved
    case needsReview = "needs_review"
    case reviewed
    case failed
    case shortRecording = "short_recording"

    public static let shortRecordingThresholdSeconds: TimeInterval = 60

    public static func finalizedStatus(
        forDuration duration: TimeInterval,
        preferredStatus: TaggingStatus,
        thresholdSeconds: TimeInterval = shortRecordingThresholdSeconds
    ) -> TaggingStatus {
        guard preferredStatus == .needsTagging,
              duration < thresholdSeconds
        else {
            return preferredStatus
        }

        return .shortRecording
    }
}

public struct RecordingSource: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleID: String
    public var trigger: String
    public var ruleID: String
    public var confidence: String?
    public var reason: String?

    public init(
        appName: String = "Manual",
        bundleID: String = "com.torbit.recorder",
        trigger: String = "manual",
        ruleID: String = "manual.stub",
        confidence: String? = nil,
        reason: String? = nil
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.trigger = trigger
        self.ruleID = ruleID
        self.confidence = confidence
        self.reason = reason
    }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleID = "bundle_id"
        case trigger
        case ruleID = "rule_id"
        case confidence
        case reason
    }
}

public struct AudioTrackMetadata: Codable, Equatable, Sendable {
    public static let completedStatus = "completed"
    public static let completedWithWarningsStatus = "completed_with_warnings"

    public var kind: String
    public var relativePath: String
    public var codec: String?
    public var container: String?
    public var durationSec: Double?
    public var sampleRate: Double?
    public var channels: Int?
    public var bitrate: Int?
    public var fileSizeBytes: Int64?
    public var signal: AudioSignalMetadata?
    public var status: String
    public var error: String?

    public init(
        kind: String,
        relativePath: String,
        codec: String? = nil,
        container: String? = nil,
        durationSec: Double? = nil,
        sampleRate: Double? = nil,
        channels: Int? = nil,
        bitrate: Int? = nil,
        fileSizeBytes: Int64? = nil,
        status: String,
        signal: AudioSignalMetadata? = nil,
        error: String? = nil
    ) {
        self.kind = kind
        self.relativePath = relativePath
        self.codec = codec
        self.container = container
        self.durationSec = durationSec
        self.sampleRate = sampleRate
        self.channels = channels
        self.bitrate = bitrate
        self.fileSizeBytes = fileSizeBytes
        self.signal = signal
        self.status = status
        self.error = error
    }

    public var isUsableCompletedTrack: Bool {
        hasCompletedStatus && (fileSizeBytes ?? 0) > 0
    }

    public var hasCompletedStatus: Bool {
        status == Self.completedStatus || status == Self.completedWithWarningsStatus
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case relativePath = "relative_path"
        case codec
        case container
        case durationSec = "duration_sec"
        case sampleRate = "sample_rate"
        case channels
        case bitrate
        case fileSizeBytes = "file_size_bytes"
        case signal
        case status
        case error
    }
}

public struct AudioProcessingMetadata: Codable, Equatable, Sendable {
    public var balancedMixStatus: BalancedMixStatus
    public var balancedMixPath: String?
    public var analysisPath: String?
    public var microphoneGainDB: Double?
    public var systemGainDB: Double?
    public var warnings: [String]

    public init(
        balancedMixStatus: BalancedMixStatus = .skipped,
        balancedMixPath: String? = nil,
        analysisPath: String? = nil,
        microphoneGainDB: Double? = nil,
        systemGainDB: Double? = nil,
        warnings: [String] = []
    ) {
        self.balancedMixStatus = balancedMixStatus
        self.balancedMixPath = balancedMixPath
        self.analysisPath = analysisPath
        self.microphoneGainDB = microphoneGainDB
        self.systemGainDB = systemGainDB
        self.warnings = warnings
    }

    public static let skipped = AudioProcessingMetadata()

    enum CodingKeys: String, CodingKey {
        case balancedMixStatus = "balanced_mix_status"
        case balancedMixPath = "balanced_mix_path"
        case analysisPath = "analysis_path"
        case microphoneGainDB = "mic_gain_db"
        case systemGainDB = "system_gain_db"
        case warnings
    }
}

public struct RecordingAudioMetadata: Codable, Equatable, Sendable {
    public var processing: AudioProcessingMetadata
    public var health: AudioHealthMetadata

    public init(
        processing: AudioProcessingMetadata = .skipped,
        health: AudioHealthMetadata = .good
    ) {
        self.processing = processing
        self.health = health
    }

    enum CodingKeys: String, CodingKey {
        case processing
        case health
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.processing = try container.decodeIfPresent(AudioProcessingMetadata.self, forKey: .processing) ?? .skipped
        self.health = try container.decodeIfPresent(AudioHealthMetadata.self, forKey: .health) ?? .good
    }
}

public enum RecordingMarkerKind: String, CaseIterable, Identifiable, Sendable {
    case important
    case objection
    case conflict
    case review
    case badAudio = "bad_audio"

    public var id: String {
        rawValue
    }

    public var label: String {
        switch self {
        case .important:
            return "Important"
        case .objection:
            return "Objection"
        case .conflict:
            return "Conflict"
        case .review:
            return "Review"
        case .badAudio:
            return "Bad audio"
        }
    }

    public var tags: [String] {
        [rawValue]
    }

    public var shortcutKey: String {
        switch self {
        case .important:
            return "1"
        case .objection:
            return "2"
        case .conflict:
            return "3"
        case .review:
            return "4"
        case .badAudio:
            return "5"
        }
    }
}

public struct RecordingMarker: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var timeSec: Double
    public var label: String
    public var tags: [String]
    public var createdAt: String

    public init(
        id: String,
        timeSec: Double,
        label: String,
        tags: [String],
        createdAt: String
    ) {
        self.id = id
        self.timeSec = max(0, timeSec.rounded(.down))
        self.label = label
        self.tags = tags
        self.createdAt = createdAt
    }

    public static func make(
        kind: RecordingMarkerKind,
        elapsedTime: TimeInterval,
        createdAt: Date = Date(),
        id: String = UUID().uuidString
    ) -> RecordingMarker {
        RecordingMarker(
            id: id,
            timeSec: elapsedTime,
            label: kind.label,
            tags: kind.tags,
            createdAt: formatISO8601(createdAt)
        )
    }

    enum CodingKeys: String, CodingKey {
        case id
        case timeSec = "time_sec"
        case label
        case tags
        case createdAt = "created_at"
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct RecordingMetadata: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var schemaVersion: Int
    public var ownerID: String
    public var workspaceID: String
    public var mentorID: String
    public var title: String
    public var startedAt: String
    public var endedAt: String
    public var durationSec: Double
    public var recordingMode: String
    public var source: RecordingSource
    public var audioTracks: [AudioTrackMetadata]
    public var participants: [String]
    public var tags: [String]
    public var category: String
    public var status: TaggingStatus
    public var markers: [RecordingMarker]
    public var qualityWarnings: [String]
    public var audio: RecordingAudioMetadata
    public var ai: String
    public var sync: String

    public init(
        id: String,
        title: String,
        startedAt: String,
        endedAt: String,
        durationSec: Double,
        audio: RecordingAudioMetadata = RecordingAudioMetadata(),
        source: RecordingSource = RecordingSource(),
        audioTracks: [AudioTrackMetadata] = [],
        category: String = "unsorted",
        status: TaggingStatus = .needsTagging,
        markers: [RecordingMarker] = [],
        qualityWarnings: [String] = [],
        participants: [String] = [],
        tags: [String] = []
    ) {
        self.id = id
        self.schemaVersion = 1
        self.ownerID = "local:vlad"
        self.workspaceID = "local:t-orbit-recorder"
        self.mentorID = "local:vlad"
        self.title = title
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.durationSec = durationSec
        self.recordingMode = "audio_only"
        self.source = source
        self.audioTracks = audioTracks
        self.participants = participants
        self.tags = tags
        self.category = category
        self.status = status
        self.markers = markers
        self.qualityWarnings = qualityWarnings
        self.audio = audio
        self.ai = "not_started"
        self.sync = "local_only"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case schemaVersion = "schema_version"
        case ownerID = "owner_id"
        case workspaceID = "workspace_id"
        case mentorID = "mentor_id"
        case title
        case startedAt = "started_at"
        case endedAt = "ended_at"
        case durationSec = "duration_sec"
        case recordingMode = "recording_mode"
        case source
        case audioTracks = "audio_tracks"
        case participants
        case tags
        case category
        case status
        case markers
        case qualityWarnings = "quality_warnings"
        case audio
        case ai
        case sync
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.schemaVersion = try container.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        self.ownerID = try container.decodeIfPresent(String.self, forKey: .ownerID) ?? "local:vlad"
        self.workspaceID = try container.decodeIfPresent(String.self, forKey: .workspaceID) ?? "local:t-orbit-recorder"
        self.mentorID = try container.decodeIfPresent(String.self, forKey: .mentorID) ?? "local:vlad"
        self.title = try container.decodeIfPresent(String.self, forKey: .title) ?? "Untitled recording"
        self.startedAt = try container.decode(String.self, forKey: .startedAt)
        self.endedAt = try container.decode(String.self, forKey: .endedAt)
        self.durationSec = try container.decodeIfPresent(Double.self, forKey: .durationSec) ?? 0
        self.recordingMode = try container.decodeIfPresent(String.self, forKey: .recordingMode) ?? "audio_only"
        self.source = try container.decodeIfPresent(RecordingSource.self, forKey: .source) ?? RecordingSource()
        self.audioTracks = try container.decodeIfPresent([AudioTrackMetadata].self, forKey: .audioTracks) ?? []
        self.participants = try container.decodeIfPresent([String].self, forKey: .participants) ?? []
        self.tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        self.category = try container.decodeIfPresent(String.self, forKey: .category) ?? "unsorted"
        self.status = try container.decodeIfPresent(TaggingStatus.self, forKey: .status) ?? .needsTagging
        self.markers = try container.decodeIfPresent([RecordingMarker].self, forKey: .markers) ?? []
        self.qualityWarnings = try container.decodeIfPresent([String].self, forKey: .qualityWarnings) ?? []
        self.audio = try container.decodeIfPresent(RecordingAudioMetadata.self, forKey: .audio) ?? RecordingAudioMetadata()
        self.ai = try container.decodeIfPresent(String.self, forKey: .ai) ?? "not_started"
        self.sync = try container.decodeIfPresent(String.self, forKey: .sync) ?? "local_only"
    }
}

public struct RecordingSession: Equatable, Identifiable, Sendable {
    public let id: String
    public let startedAt: Date
    public let source: RecordingSource
    public let folderURL: URL
    public let sourceURL: URL
    public let exportURL: URL
    public let segmentsURL: URL
    public let metadataURL: URL
    public let recoveryMetadataURL: URL

    public init(
        id: String,
        startedAt: Date,
        source: RecordingSource,
        folderURL: URL
    ) {
        self.id = id
        self.startedAt = startedAt
        self.source = source
        self.folderURL = folderURL
        self.sourceURL = folderURL.appendingPathComponent("source", isDirectory: true)
        self.exportURL = folderURL.appendingPathComponent("export", isDirectory: true)
        self.segmentsURL = self.sourceURL.appendingPathComponent("segments", isDirectory: true)
        self.metadataURL = folderURL.appendingPathComponent("metadata.json")
        self.recoveryMetadataURL = folderURL.appendingPathComponent("recovery.json")
    }
}

public struct PostCallDraft: Equatable, Identifiable, Sendable {
    public let id: String
    public var title: String
    public var category: String
    public var participant: String
    public var tags: [String]
    public var status: TaggingStatus
    public let sessionFolderURL: URL
    public let metadataURL: URL

    public init(
        id: String,
        title: String,
        category: String,
        participant: String,
        tags: [String],
        status: TaggingStatus,
        sessionFolderURL: URL,
        metadataURL: URL
    ) {
        self.id = id
        self.title = title
        self.category = category
        self.participant = participant
        self.tags = tags
        self.status = status
        self.sessionFolderURL = sessionFolderURL
        self.metadataURL = metadataURL
    }
}

public struct RecordingSummary: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let category: String
    public let participant: String
    public let tags: [String]
    public let status: TaggingStatus
    public let sourceApp: String
    public let startedAt: String
    public let endedAt: String
    public let durationSec: Double
    public let metadataURL: URL
    public let sessionFolderURL: URL

    public var mixedAudioURL: URL {
        RecordingPlaybackResolver.preferredPlayback(
            sessionFolderURL: sessionFolderURL
        )?.url ?? originalMixedAudioURL
    }

    public var originalMixedAudioURL: URL {
        RecordingPlaybackResolver.originalMixedURL(sessionFolderURL: sessionFolderURL)
    }

    public var balancedMixedAudioURL: URL {
        RecordingPlaybackResolver.balancedMixedURL(sessionFolderURL: sessionFolderURL)
    }

    public var audioAnalysisURL: URL {
        RecordingPlaybackResolver.audioAnalysisURL(sessionFolderURL: sessionFolderURL)
    }
}

public struct LastRecordingSummary: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: TaggingStatus
    public let durationSec: Double
    public let folderName: String
    public let sessionFolderURL: URL
    public let metadataURL: URL
    public let micFileSizeBytes: Int64?
    public let systemFileSizeBytes: Int64?
    public let mixedFileSizeBytes: Int64?
    public let balancedMixedFileSizeBytes: Int64?
    public let micTrackStatus: String?
    public let systemTrackStatus: String?
    public let mixedTrackStatus: String?
    public let balancedMixedTrackStatus: String?
    public let audioProcessingStatus: BalancedMixStatus
    public let audioProcessingWarnings: [String]
    public let audioHealthStatus: AudioHealthStatus
    public let audioHealthWarnings: [AudioHealthWarning]
    public let startConfidence: String?
    public let startReason: String?
    public let qualityWarnings: [String]
    public let tags: [String]

    public var mixedAudioURL: URL {
        RecordingPlaybackResolver.preferredPlayback(
            sessionFolderURL: sessionFolderURL,
            processingStatus: audioProcessingStatus
        )?.url ?? originalMixedAudioURL
    }

    public var originalMixedAudioURL: URL {
        RecordingPlaybackResolver.originalMixedURL(sessionFolderURL: sessionFolderURL)
    }

    public var balancedMixedAudioURL: URL {
        RecordingPlaybackResolver.balancedMixedURL(sessionFolderURL: sessionFolderURL)
    }

    public var audioAnalysisURL: URL {
        RecordingPlaybackResolver.audioAnalysisURL(sessionFolderURL: sessionFolderURL)
    }

    public var playbackDisplayState: RecordingPlaybackDisplayState {
        RecordingPlaybackResolver.displayState(
            sessionFolderURL: sessionFolderURL,
            processingStatus: audioProcessingStatus
        )
    }

    public var displayStatus: String {
        RecordingDisplayFormatter.statusText(status)
    }

    public var mixedPreviewState: String {
        if RecordingPlaybackResolver.preferredPlayback(
            sessionFolderURL: sessionFolderURL,
            processingStatus: audioProcessingStatus
        ) != nil {
            return "Ready"
        }

        if mixedTrackStatus == "failed" && balancedMixedTrackStatus == "failed" {
            return "Failed"
        }

        if (mixedFileSizeBytes ?? 0) > 0 {
            return "Ready"
        }

        return "Missing"
    }
}

public struct RecordingListFilters: Equatable, Sendable {
    public var dateText: String
    public var status: TaggingStatus?
    public var sourceAppText: String
    public var titleText: String
    public var tags: [String]

    public init(
        dateText: String = "",
        status: TaggingStatus? = nil,
        sourceAppText: String = "",
        titleText: String = "",
        tags: [String] = []
    ) {
        self.dateText = dateText
        self.status = status
        self.sourceAppText = sourceAppText
        self.titleText = titleText
        self.tags = tags
    }
}
