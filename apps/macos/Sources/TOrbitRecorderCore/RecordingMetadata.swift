import Foundation

public enum TaggingStatus: String, CaseIterable, Codable, Sendable {
    case needsTagging = "needs_tagging"
    case saved
    case needsReview = "needs_review"
    case reviewed
    case failed
}

public struct RecordingSource: Codable, Equatable, Sendable {
    public var appName: String
    public var bundleID: String
    public var trigger: String
    public var ruleID: String

    public init(
        appName: String = "Manual",
        bundleID: String = "com.torbit.recorder",
        trigger: String = "manual",
        ruleID: String = "manual.stub"
    ) {
        self.appName = appName
        self.bundleID = bundleID
        self.trigger = trigger
        self.ruleID = ruleID
    }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case bundleID = "bundle_id"
        case trigger
        case ruleID = "rule_id"
    }
}

public struct AudioTrackMetadata: Codable, Equatable, Sendable {
    public var kind: String
    public var relativePath: String
    public var codec: String?
    public var container: String?
    public var durationSec: Double?
    public var sampleRate: Double?
    public var channels: Int?
    public var bitrate: Int?
    public var fileSizeBytes: Int64?
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
        self.status = status
        self.error = error
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
        case status
        case error
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
    public var ai: String
    public var sync: String

    public init(
        id: String,
        title: String,
        startedAt: String,
        endedAt: String,
        durationSec: Double,
        source: RecordingSource = RecordingSource(),
        audioTracks: [AudioTrackMetadata] = [],
        category: String = "unsorted",
        status: TaggingStatus = .needsTagging,
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
        case ai
        case sync
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
        sessionFolderURL
            .appendingPathComponent("export", isDirectory: true)
            .appendingPathComponent("mixed.m4a")
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
