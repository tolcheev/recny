import AVFoundation
import Foundation

@MainActor
public final class MacOSAudioRecordingController: NSObject, RecordingController, AVAudioRecorderDelegate {
    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var microphoneRecorder: AVAudioRecorder?
    private var systemAudioRecorder: ScreenCaptureKitSystemAudioRecorder?

    public override init() {}

    public func startRecording(outputFolder: URL) async throws -> RecordingControllerUpdate {
        guard startedAt == nil else {
            throw RecordingControllerError.alreadyRecording
        }

        try await ensureMicrophonePermission()
        try ensureInputDeviceAvailable()

        let startDate = Date()
        let store = FileSystemRecordingStore(rootURL: outputFolder)
        let session = try store.startSession(
            startedAt: startDate,
            source: RecordingSource(
                appName: "TOrbitRecorder",
                bundleID: "com.torbit.recorder",
                trigger: "manual",
                ruleID: "manual.audio"
            )
        )

        let micURL = session.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = session.sourceURL.appendingPathComponent("system.m4a")
        let micRecorder = try AVAudioRecorder(
            url: micURL,
            settings: AVFoundationMicrophoneRecordingController.audioRecorderSettings
        )
        micRecorder.delegate = self

        let systemRecorder = ScreenCaptureKitSystemAudioRecorder()
        try await systemRecorder.start(outputURL: systemURL)

        guard micRecorder.prepareToRecord(), micRecorder.record() else {
            _ = try? await systemRecorder.stop()
            throw RecordingControllerError.recorderSetupFailed("AVAudioRecorder failed to start")
        }

        self.startedAt = startDate
        self.activeSession = session
        self.store = store
        self.microphoneRecorder = micRecorder
        self.systemAudioRecorder = systemRecorder

        AppLogger.recording.info("Microphone and system audio recording started")

        return RecordingControllerUpdate(
            status: .recording,
            micStatus: .recording,
            systemAudioStatus: .recording,
            startedAt: startDate,
            duration: 0,
            session: session
        )
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt,
              let activeSession,
              let store,
              let microphoneRecorder,
              let systemAudioRecorder
        else {
            throw RecordingControllerError.notRecording
        }
        defer {
            clearActiveRecordingState()
        }

        microphoneRecorder.stop()
        let systemResult = try await systemAudioRecorder.stop()

        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let micURL = activeSession.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = activeSession.sourceURL.appendingPathComponent("system.m4a")

        try validateRecordedFile(at: micURL, kind: "microphone")
        try validateRecordedFile(at: systemURL, kind: "system")

        let audioTracks = [
            AudioTrackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                codec: "aac",
                container: "m4a",
                durationSec: duration,
                sampleRate: AVFoundationMicrophoneRecordingController.sampleRate,
                channels: AVFoundationMicrophoneRecordingController.channels,
                bitrate: AVFoundationMicrophoneRecordingController.bitrate,
                status: "completed"
            ),
            AudioTrackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                codec: "aac",
                container: "m4a",
                durationSec: systemResult.duration > 0 ? systemResult.duration : duration,
                sampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
                channels: ScreenCaptureKitSystemAudioRecorder.channels,
                bitrate: ScreenCaptureKitSystemAudioRecorder.bitrate,
                status: "completed"
            )
        ]
        let draft = try store.stopSession(
            activeSession,
            endedAt: endedAt,
            duration: duration,
            status: .needsTagging,
            audioTracks: audioTracks
        )

        AppLogger.recording.info("Microphone and system audio recording stopped after \(duration, privacy: .public) seconds")

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration,
            postCallDraft: draft
        )
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied, .restricted:
            throw RecordingControllerError.microphonePermissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                throw RecordingControllerError.microphonePermissionDenied
            }
        @unknown default:
            throw RecordingControllerError.microphonePermissionDenied
        }
    }

    private func ensureInputDeviceAvailable() throws {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            throw RecordingControllerError.noInputDevice
        }
    }

    private func validateRecordedFile(at url: URL, kind: String) throws {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RecordingControllerError.fileWriteFailed("Missing \(kind) file at \(path)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as? NSNumber
        guard let size, size.int64Value > 0 else {
            throw RecordingControllerError.fileWriteFailed("Empty \(kind) file at \(path)")
        }
    }

    private func clearActiveRecordingState() {
        startedAt = nil
        activeSession = nil
        store = nil
        microphoneRecorder = nil
        systemAudioRecorder = nil
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            AppLogger.recording.error("Microphone recorder encode error: \(String(describing: error), privacy: .public)")
        }
    }
}
