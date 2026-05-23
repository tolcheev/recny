import Foundation

public enum RecoveryStatus: String, Codable, Sendable {
    case recording
    case recoverable
    case recovered
    case completed
    case failed
}

public struct RecoverySegmentMetadata: Codable, Equatable, Sendable {
    public var kind: String
    public var relativePath: String
    public var status: String
    public var fileSizeBytes: Int64?
    public var updatedAt: String?

    public init(
        kind: String,
        relativePath: String,
        status: String,
        fileSizeBytes: Int64? = nil,
        updatedAt: String? = nil
    ) {
        self.kind = kind
        self.relativePath = relativePath
        self.status = status
        self.fileSizeBytes = fileSizeBytes
        self.updatedAt = updatedAt
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case relativePath = "relative_path"
        case status
        case fileSizeBytes = "file_size_bytes"
        case updatedAt = "updated_at"
    }
}

public struct RecoveryMetadata: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var recordingID: String
    public var status: RecoveryStatus
    public var startedAt: String
    public var updatedAt: String
    public var source: RecordingSource
    public var segments: [RecoverySegmentMetadata]
    public var error: String?

    public init(
        recordingID: String,
        status: RecoveryStatus,
        startedAt: String,
        updatedAt: String,
        source: RecordingSource,
        segments: [RecoverySegmentMetadata],
        error: String? = nil
    ) {
        self.schemaVersion = 1
        self.recordingID = recordingID
        self.status = status
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.source = source
        self.segments = segments
        self.error = error
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordingID = "recording_id"
        case status
        case startedAt = "started_at"
        case updatedAt = "updated_at"
        case source
        case segments
        case error
    }
}

public struct RecoverableRecordingSummary: Equatable, Identifiable, Sendable {
    public let id: String
    public let status: RecoveryStatus
    public let startedAt: String
    public let updatedAt: String
    public let folderURL: URL
    public let recoveryMetadataURL: URL
    public let segmentCount: Int
}
