import Foundation

@MainActor
public final class StubRecordingController: RecordingController {
    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?

    public init() {}

    public func startRecording(outputFolder: URL) async throws -> RecordingControllerUpdate {
        guard startedAt == nil else {
            throw RecordingControllerError.alreadyRecording
        }

        let startDate = Date()
        let store = FileSystemRecordingStore(rootURL: outputFolder)
        let session = try store.startSession(
            startedAt: startDate,
            source: RecordingSource()
        )

        startedAt = startDate
        activeSession = session
        self.store = store

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
        let draft = try store.stopSession(
            activeSession,
            endedAt: Date(),
            duration: duration,
            status: .needsTagging
        )

        self.startedAt = nil
        self.activeSession = nil
        self.store = nil

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
