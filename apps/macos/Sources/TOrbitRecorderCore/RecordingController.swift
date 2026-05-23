import Foundation

public enum RecordingStatus: String, CaseIterable, Sendable {
    case idle = "Idle"
    case recording = "Recording"
    case error = "Error"
}

public enum CaptureStatus: String, CaseIterable, Sendable {
    case idle = "Idle"
    case ready = "Ready"
    case error = "Error"
}

public enum RecordingControllerError: Error, Equatable, Sendable {
    case alreadyRecording
    case notRecording
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
