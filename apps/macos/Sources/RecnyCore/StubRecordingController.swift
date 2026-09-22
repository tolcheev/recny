import Foundation

@MainActor
public final class StubRecordingController: RecordingController {
    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var runtimeSettings = RecordingRuntimeSettings()

    public init() {}

    public func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate {
        guard startedAt == nil else {
            throw RecordingControllerError.alreadyRecording
        }

        let startDate = Date()
        let store = FileSystemRecordingStore(rootURL: outputFolder)
        let session = try store.startSession(
            startedAt: startDate,
            source: source
        )

        startedAt = startDate
        activeSession = session
        self.store = store
        runtimeSettings = settings

        AppLogger.recording.info(
            "Stub recording started; session folder created. outputFolder=\(outputFolder.path(percentEncoded: false), privacy: .public)"
        )

        return RecordingControllerUpdate(
            status: .recording,
            micStatus: .ready,
            systemAudioStatus: .ready,
            startedAt: startDate,
            duration: 0,
            session: session
        )
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt, let activeSession, let store else {
            throw RecordingControllerError.notRecording
        }

        let duration = Date().timeIntervalSince(startedAt)
        let sessionStatus = TaggingStatus.finalizedStatus(
            forDuration: duration,
            preferredStatus: .needsTagging,
            thresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
        )
        let draft = try store.stopSession(
            activeSession,
            endedAt: Date(),
            duration: duration,
            status: sessionStatus,
            shortRecordingThresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
        )

        self.startedAt = nil
        self.activeSession = nil
        self.store = nil
        self.runtimeSettings = RecordingRuntimeSettings()

        AppLogger.recording.info(
            "Stub recording stopped after \(duration, privacy: .public) seconds; metadata written."
        )

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration,
            postCallDraft: draft
        )
    }
}
