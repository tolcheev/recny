import AVFoundation
import Foundation

@MainActor
public final class AVFoundationMicrophoneRecordingController: NSObject, RecordingController, AVAudioRecorderDelegate {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 1
    public static let bitrate: Int = 128_000

    public static var audioRecorderSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate
        ]
    }

    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var recorder: AVAudioRecorder?

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
                ruleID: "manual.microphone"
            )
        )

        let micURL = session.sourceURL.appendingPathComponent("mic.m4a")
        let recorder = try AVAudioRecorder(url: micURL, settings: Self.audioRecorderSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = false

        guard recorder.prepareToRecord(), recorder.record() else {
            throw RecordingControllerError.recorderSetupFailed("AVAudioRecorder failed to start")
        }

        self.startedAt = startDate
        self.activeSession = session
        self.store = store
        self.recorder = recorder

        AppLogger.recording.info("Microphone recording started: \(micURL.path(percentEncoded: false), privacy: .public)")

        return RecordingControllerUpdate(
            status: .recording,
            micStatus: .recording,
            systemAudioStatus: .idle,
            startedAt: startDate,
            duration: 0,
            session: session
        )
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt, let activeSession, let store, let recorder else {
            throw RecordingControllerError.notRecording
        }

        recorder.stop()

        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let micURL = activeSession.sourceURL.appendingPathComponent("mic.m4a")

        try validateRecordedFile(at: micURL)

        let micTrack = AudioTrackMetadata(
            kind: "microphone",
            relativePath: "source/mic.m4a",
            codec: "aac",
            container: "m4a",
            durationSec: duration,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            bitrate: Self.bitrate,
            status: "completed"
        )
        let draft = try store.stopSession(
            activeSession,
            endedAt: endedAt,
            duration: duration,
            status: .needsTagging,
            audioTracks: [micTrack]
        )

        self.startedAt = nil
        self.activeSession = nil
        self.store = nil
        self.recorder = nil

        AppLogger.recording.info("Microphone recording stopped after \(duration, privacy: .public) seconds")

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
            AppLogger.recording.error("Microphone permission denied or restricted")
            throw RecordingControllerError.microphonePermissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                AppLogger.recording.error("Microphone permission request denied")
                throw RecordingControllerError.microphonePermissionDenied
            }
        @unknown default:
            throw RecordingControllerError.microphonePermissionDenied
        }
    }

    private func ensureInputDeviceAvailable() throws {
        guard AVCaptureDevice.default(for: .audio) != nil else {
            AppLogger.recording.error("No microphone input device available")
            throw RecordingControllerError.noInputDevice
        }
    }

    private func validateRecordedFile(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RecordingControllerError.fileWriteFailed("Missing file at \(path)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as? NSNumber
        guard let size, size.int64Value > 0 else {
            throw RecordingControllerError.fileWriteFailed("Empty file at \(path)")
        }
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            AppLogger.recording.error("Microphone recorder encode error: \(String(describing: error), privacy: .public)")
        }
    }
}
