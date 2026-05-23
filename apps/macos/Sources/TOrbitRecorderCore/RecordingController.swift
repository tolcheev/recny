import Foundation

public enum RecordingStatus: String, CaseIterable, Sendable {
    case idle = "Idle"
    case recording = "Recording"
    case error = "Error"
}

public enum CaptureStatus: String, CaseIterable, Sendable {
    case idle = "Idle"
    case ready = "Ready"
    case recording = "Recording"
    case permissionDenied = "Permission Denied"
    case noInputDevice = "No Input Device"
    case error = "Error"
}

public enum RecordingControllerError: Error, Equatable, Sendable, CustomStringConvertible {
    case alreadyRecording
    case notRecording
    case microphonePermissionDenied
    case noInputDevice
    case recorderSetupFailed(String)
    case fileWriteFailed(String)

    public var description: String {
        switch self {
        case .alreadyRecording:
            return "Recording is already active"
        case .notRecording:
            return "No active recording"
        case .microphonePermissionDenied:
            return "Microphone permission is denied"
        case .noInputDevice:
            return "No microphone input device is available"
        case .recorderSetupFailed(let message):
            return "Failed to configure microphone recorder: \(message)"
        case .fileWriteFailed(let message):
            return "Failed to write microphone recording: \(message)"
        }
    }
}

public struct RecordingControllerUpdate: Equatable, Sendable {
    public let status: RecordingStatus
    public let micStatus: CaptureStatus
    public let systemAudioStatus: CaptureStatus
    public let startedAt: Date?
    public let duration: TimeInterval?
    public let session: RecordingSession?
    public let postCallDraft: PostCallDraft?

    public init(
        status: RecordingStatus,
        micStatus: CaptureStatus,
        systemAudioStatus: CaptureStatus,
        startedAt: Date? = nil,
        duration: TimeInterval? = nil,
        session: RecordingSession? = nil,
        postCallDraft: PostCallDraft? = nil
    ) {
        self.status = status
        self.micStatus = micStatus
        self.systemAudioStatus = systemAudioStatus
        self.startedAt = startedAt
        self.duration = duration
        self.session = session
        self.postCallDraft = postCallDraft
    }
}

@MainActor
public protocol RecordingController {
    func startRecording(outputFolder: URL) async throws -> RecordingControllerUpdate
    func stopRecording() async throws -> RecordingControllerUpdate
}
