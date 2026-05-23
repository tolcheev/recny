import Foundation

@MainActor
public final class StubRecordingController: RecordingController {
    private var startedAt: Date?

    public init() {}

    public func startRecording(outputFolder: URL) async throws -> RecordingControllerUpdate {
        guard startedAt == nil else {
            throw RecordingControllerError.alreadyRecording
        }

        let startDate = Date()
        startedAt = startDate

        AppLogger.recording.info(
            "Stub recording started; no audio will be written. outputFolder=\(outputFolder.path(percentEncoded: false), privacy: .public)"
        )

        return RecordingControllerUpdate(
            status: .recording,
            micStatus: .ready,
            systemAudioStatus: .ready,
            startedAt: startDate,
            duration: 0
        )
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt else {
            throw RecordingControllerError.notRecording
        }

        let duration = Date().timeIntervalSince(startedAt)
        self.startedAt = nil

        AppLogger.recording.info(
            "Stub recording stopped after \(duration, privacy: .public) seconds; no audio was written."
        )

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration
        )
    }
}
