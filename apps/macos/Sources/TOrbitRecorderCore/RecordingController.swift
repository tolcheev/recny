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
    case systemAudioPermissionDenied(String)
    case noShareableDisplay
    case recorderSetupFailed(String)
    case fileWriteFailed(String)
    case systemAudioSetupFailed(String)
    case systemAudioWriteFailed(String)
    case systemAudioNoSamples
    case mixedAudioNoSourceTracks
    case mixedAudioSetupFailed(String)
    case mixedAudioWriteFailed(String)
    case preflightFailed(String)

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
        case .systemAudioPermissionDenied(let message):
            return "System audio permission is unavailable: \(message)"
        case .noShareableDisplay:
            return "No system audio capture source is available"
        case .recorderSetupFailed(let message):
            return "Failed to configure microphone recorder: \(message)"
        case .fileWriteFailed(let message):
            return "Failed to write microphone recording: \(message)"
        case .systemAudioSetupFailed(let message):
            return "Failed to configure system audio recorder: \(message)"
        case .systemAudioWriteFailed(let message):
            return "Failed to write system audio recording: \(message)"
        case .systemAudioNoSamples:
            return "System audio capture produced no samples"
        case .mixedAudioNoSourceTracks:
            return "Cannot create mixed audio preview because no source tracks are available"
        case .mixedAudioSetupFailed(let message):
            return "Failed to configure mixed audio preview: \(message)"
        case .mixedAudioWriteFailed(let message):
            return "Failed to write mixed audio preview: \(message)"
        case .preflightFailed(let message):
            return "Recording preflight failed: \(message)"
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

public struct AudioLevelSnapshot: Equatable, Sendable {
    public let microphoneLevel: Float
    public let systemAudioLevel: Float

    public init(
        microphoneLevel: Float = 0,
        systemAudioLevel: Float = 0
    ) {
        self.microphoneLevel = min(1, max(0, microphoneLevel))
        self.systemAudioLevel = min(1, max(0, systemAudioLevel))
    }
}

@MainActor
public protocol RecordingController {
    func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate
    func stopRecording() async throws -> RecordingControllerUpdate
    func currentAudioLevels() -> AudioLevelSnapshot
}

@MainActor
public extension RecordingController {
    func currentAudioLevels() -> AudioLevelSnapshot {
        AudioLevelSnapshot()
    }

    func startRecording(outputFolder: URL, source: RecordingSource) async throws -> RecordingControllerUpdate {
        try await startRecording(
            outputFolder: outputFolder,
            source: source,
            settings: RecordingRuntimeSettings()
        )
    }

    func startRecording(outputFolder: URL) async throws -> RecordingControllerUpdate {
        try await startRecording(
            outputFolder: outputFolder,
            source: RecordingSource(
                appName: "ToRec",
                bundleID: "com.torbit.recorder",
                trigger: "manual",
                ruleID: "manual.audio"
            ),
            settings: RecordingRuntimeSettings()
        )
    }
}
