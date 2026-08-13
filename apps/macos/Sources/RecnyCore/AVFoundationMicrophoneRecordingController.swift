import AVFoundation
import Foundation

@MainActor
public final class AVFoundationMicrophoneRecordingController: NSObject, RecordingController, AVAudioRecorderDelegate {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 1
    public static let bitrate: Int = 128_000

    public static var audioRecorderSettings: [String: Any] {
        audioRecorderSettings(for: .standard)
    }

    public static func audioRecorderSettings(for preset: AudioQualityPreset) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: preset.sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: preset.microphoneBitrate
        ]
    }

    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var recorder: AVAudioRecorder?
    private var microphoneInputOverride: CoreAudioInputDeviceOverride?
    private var runtimeSettings = RecordingRuntimeSettings()

    public override init() {}

    public func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate {
        guard startedAt == nil else {
            throw RecordingControllerError.alreadyRecording
        }

        try await ensureMicrophonePermission()
        let microphoneSelection = try selectMicrophoneInput(settings: settings)

        do {
            let startDate = Date()
            let store = FileSystemRecordingStore(rootURL: outputFolder)
            let session = try store.startSession(
                startedAt: startDate,
                source: source
            )

            let micSegmentURL = session.segmentsURL.appendingPathComponent("mic-0001.m4a")
            let recorder = try AVAudioRecorder(
                url: micSegmentURL,
                settings: Self.audioRecorderSettings(for: settings.audioQualityPreset)
            )
            recorder.delegate = self
            recorder.isMeteringEnabled = true

            guard recorder.prepareToRecord(), recorder.record() else {
                throw RecordingControllerError.recorderSetupFailed("AVAudioRecorder failed to start")
            }

            self.startedAt = startDate
            self.activeSession = session
            self.store = store
            self.recorder = recorder
            self.runtimeSettings = settings

            AppLogger.recording.info("Microphone recording started: \(micSegmentURL.path(percentEncoded: false), privacy: .public)")
            if let warning = microphoneSelection.warning {
                AppLogger.recording.error("\(warning, privacy: .public)")
            }

            return RecordingControllerUpdate(
                status: .recording,
                micStatus: .recording,
                systemAudioStatus: .idle,
                startedAt: startDate,
                duration: 0,
                session: session
            )
        } catch {
            clearActiveRecordingState()
            throw error
        }
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt, let activeSession, let store, let recorder else {
            throw RecordingControllerError.notRecording
        }
        defer {
            clearActiveRecordingState()
        }

        recorder.stop()

        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let micURL = activeSession.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = activeSession.sourceURL.appendingPathComponent("system.m4a")
        let mixedURL = activeSession.exportURL.appendingPathComponent("mixed.m4a")
        let micSegmentURL = activeSession.segmentsURL.appendingPathComponent("mic-0001.m4a")

        try finalizeSegmentIfUsable(from: micSegmentURL, to: micURL)

        let micFileSize = try validateRecordedFile(at: micURL)

        let micTrack = AudioTrackMetadata(
            kind: "microphone",
            relativePath: "source/mic.m4a",
            codec: "aac",
            container: "m4a",
            durationSec: duration,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            bitrate: runtimeSettings.audioQualityPreset.microphoneBitrate,
            fileSizeBytes: micFileSize,
            status: "completed",
            signal: AudioSignalAnalyzer.analyze(url: micURL)
        )
        let mixedTrack: AudioTrackMetadata
        let sessionStatus: TaggingStatus
        if !runtimeSettings.mixedPreviewEnabled {
            mixedTrack = AudioTrackMetadata(
                kind: "mixed",
                relativePath: "export/mixed.m4a",
                codec: "aac",
                container: "m4a",
                sampleRate: MixedAudioPreviewGenerator.sampleRate,
                channels: MixedAudioPreviewGenerator.channels,
                bitrate: runtimeSettings.audioQualityPreset.mixedPreviewBitrate,
                status: "disabled",
                error: "mixed preview disabled in settings"
            )
            sessionStatus = TaggingStatus.finalizedStatus(
                forDuration: duration,
                preferredStatus: .needsTagging,
                thresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
            )
        } else {
            do {
                mixedTrack = try await MixedAudioPreviewGenerator()
                    .createPreview(
                        micURL: micURL,
                        systemURL: systemURL,
                        outputURL: mixedURL,
                        qualityPreset: runtimeSettings.audioQualityPreset
                    )
                    .track
                sessionStatus = TaggingStatus.finalizedStatus(
                    forDuration: duration,
                    preferredStatus: .needsTagging,
                    thresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
                )
            } catch {
                AppLogger.recording.error("Mixed audio preview failed for microphone recording: \(String(describing: error), privacy: .public)")
                mixedTrack = AudioTrackMetadata(
                    kind: "mixed",
                    relativePath: "export/mixed.m4a",
                    codec: "aac",
                    container: "m4a",
                    sampleRate: MixedAudioPreviewGenerator.sampleRate,
                    channels: MixedAudioPreviewGenerator.channels,
                    bitrate: runtimeSettings.audioQualityPreset.mixedPreviewBitrate,
                    status: "failed",
                    error: String(describing: error)
                )
                sessionStatus = .failed
            }
        }
        try updateRecoveryMetadata(
            for: activeSession,
            status: sessionStatus == .failed ? .failed : .completed,
            error: sessionStatus == .failed ? mixedTrack.error : nil
        )
        let draft = try store.stopSession(
            activeSession,
            endedAt: endedAt,
            duration: duration,
            status: sessionStatus,
            audioTracks: [micTrack, mixedTrack],
            shortRecordingThresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
        )

        AppLogger.recording.info("Microphone recording stopped after \(duration, privacy: .public) seconds")

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration,
            postCallDraft: draft
        )
    }

    public func currentAudioLevels() -> AudioLevelSnapshot {
        guard let recorder, recorder.isRecording else {
            return AudioLevelSnapshot()
        }

        recorder.updateMeters()
        return AudioLevelSnapshot(
            microphoneLevel: Self.normalizedLevel(fromAveragePower: recorder.averagePower(forChannel: 0)),
            systemAudioLevel: 0
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

    private func selectMicrophoneInput(settings: RecordingRuntimeSettings) throws -> MicrophoneDeviceSelection {
        let devices = MicrophoneDeviceProvider.availableInputDevices()
        guard let selection = DevicePriorityResolver.resolve(
            devices: devices,
            preferredDeviceID: settings.preferredMicrophoneDeviceID
        ) else {
            AppLogger.recording.error("No microphone input device available")
            throw RecordingControllerError.noInputDevice
        }

        #if canImport(CoreAudio)
        microphoneInputOverride = try CoreAudioInputDeviceOverride(selectedDeviceUID: selection.device.id)
        #endif
        return selection
    }

    private func validateRecordedFile(at url: URL) throws -> Int64 {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            throw RecordingControllerError.fileWriteFailed("Missing file at \(path)")
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as? NSNumber
        guard let size, size.int64Value > 0 else {
            throw RecordingControllerError.fileWriteFailed("Empty file at \(path)")
        }
        return size.int64Value
    }

    private func finalizeSegmentIfUsable(from segmentURL: URL, to finalURL: URL) throws {
        let segmentPath = segmentURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: segmentPath) else {
            return
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: segmentPath)
        let size = attributes[.size] as? NSNumber
        guard let size, size.int64Value > 0 else {
            return
        }

        try FileManager.default.removeItemIfExists(at: finalURL)
        try FileManager.default.copyItem(at: segmentURL, to: finalURL)
    }

    private func updateRecoveryMetadata(
        for session: RecordingSession,
        status: RecoveryStatus,
        error: String?
    ) throws {
        guard var recovery = try store?.readRecoveryMetadata(at: session.recoveryMetadataURL) else {
            return
        }

        let updatedAt = iso8601(Date())
        recovery.status = status
        recovery.updatedAt = updatedAt
        recovery.error = error
        recovery.segments = recovery.segments.map { segment in
            var updated = segment
            let url = session.folderURL.appendingPathComponent(segment.relativePath)
            let size = (try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber)?.int64Value
            updated.fileSizeBytes = size
            updated.status = (size ?? 0) > 0 ? "completed" : "missing"
            updated.updatedAt = updatedAt
            return updated
        }
        try store?.writeRecoveryMetadata(recovery, to: session.recoveryMetadataURL)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func clearActiveRecordingState() {
        startedAt = nil
        activeSession = nil
        store = nil
        recorder = nil
        microphoneInputOverride?.restore()
        microphoneInputOverride = nil
        runtimeSettings = RecordingRuntimeSettings()
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            AppLogger.recording.error("Microphone recorder encode error: \(String(describing: error), privacy: .public)")
        }
    }
}

private extension AVFoundationMicrophoneRecordingController {
    static func normalizedLevel(fromAveragePower power: Float) -> Float {
        guard power.isFinite else {
            return 0
        }

        if power <= -60 {
            return 0
        }

        return min(1, max(0, (power + 60) / 60))
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        if fileExists(atPath: path) {
            try removeItem(at: url)
        }
    }
}
