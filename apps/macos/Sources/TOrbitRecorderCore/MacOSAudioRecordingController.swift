import AVFoundation
import Foundation

@MainActor
public final class MacOSAudioRecordingController: NSObject, RecordingController, AVAudioRecorderDelegate {
    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var microphoneRecorder: AVAudioRecorder?
    private var systemAudioRecorder: ScreenCaptureKitSystemAudioRecorder?
    private var microphoneInputOverride: CoreAudioInputDeviceOverride?
    private let mixedAudioPreviewGenerator: MixedAudioPreviewGenerator
    private var runtimeSettings = RecordingRuntimeSettings()
    private var selectedMicrophoneDevice: MicrophoneDeviceSelection?

    public override init() {
        self.mixedAudioPreviewGenerator = MixedAudioPreviewGenerator()
        super.init()
    }

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
            let systemSegmentURL = session.segmentsURL.appendingPathComponent("system-0001.m4a")
            let micRecorder = try AVAudioRecorder(
                url: micSegmentURL,
                settings: AVFoundationMicrophoneRecordingController.audioRecorderSettings(for: settings.audioQualityPreset)
            )
            micRecorder.delegate = self
            micRecorder.isMeteringEnabled = true

            let systemRecorder: ScreenCaptureKitSystemAudioRecorder?
            if settings.systemAudioEnabled {
                let recorder = ScreenCaptureKitSystemAudioRecorder()
                try await recorder.start(
                    outputURL: systemSegmentURL,
                    qualityPreset: settings.audioQualityPreset
                )
                systemRecorder = recorder
            } else {
                systemRecorder = nil
            }

            guard micRecorder.prepareToRecord(), micRecorder.record() else {
                _ = try? await systemRecorder?.stop()
                throw RecordingControllerError.recorderSetupFailed("AVAudioRecorder failed to start")
            }

            self.startedAt = startDate
            self.activeSession = session
            self.store = store
            self.microphoneRecorder = micRecorder
            self.systemAudioRecorder = systemRecorder
            self.selectedMicrophoneDevice = microphoneSelection
            self.runtimeSettings = settings

            AppLogger.recording.info("Microphone recording started. mic=\(microphoneSelection.device.name, privacy: .public), system_audio_enabled=\(settings.systemAudioEnabled, privacy: .public), mixed_preview_enabled=\(settings.mixedPreviewEnabled, privacy: .public)")
            AppLogger.file(.info, category: "recording", "writer ready mic=\(microphoneSelection.device.name) mic_segment=\(micSegmentURL.path(percentEncoded: false)) system_segment=\(systemSegmentURL.path(percentEncoded: false)) system_audio_enabled=\(settings.systemAudioEnabled) mixed_preview_enabled=\(settings.mixedPreviewEnabled)")
            if let warning = microphoneSelection.warning {
                AppLogger.recording.error("\(warning, privacy: .public)")
                AppLogger.file(.warning, category: "recording", warning)
            }

            return RecordingControllerUpdate(
                status: .recording,
                micStatus: .recording,
                systemAudioStatus: settings.systemAudioEnabled ? .recording : .idle,
                startedAt: startDate,
                duration: 0,
                session: session
            )
        } catch {
            microphoneInputOverride?.restore()
            microphoneInputOverride = nil
            selectedMicrophoneDevice = nil
            throw error
        }
    }

    public func stopRecording() async throws -> RecordingControllerUpdate {
        guard let startedAt,
              let activeSession,
              let store,
              let microphoneRecorder
        else {
            throw RecordingControllerError.notRecording
        }
        defer {
            clearActiveRecordingState()
        }

        microphoneRecorder.stop()

        let systemResult: Result<SystemAudioRecordingResult, Error>?
        if let systemAudioRecorder {
            do {
                systemResult = .success(try await systemAudioRecorder.stop())
            } catch {
                AppLogger.recording.error("System audio stop failed: \(String(describing: error), privacy: .public)")
                AppLogger.file(.error, category: "recording", "system audio stop failed error=\(String(describing: error))")
                systemResult = .failure(error)
            }
        } else {
            systemResult = nil
        }

        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let micURL = activeSession.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = activeSession.sourceURL.appendingPathComponent("system.m4a")
        let mixedURL = activeSession.exportURL.appendingPathComponent("mixed.m4a")
        let micSegmentURL = activeSession.segmentsURL.appendingPathComponent("mic-0001.m4a")
        let systemSegmentURL = activeSession.segmentsURL.appendingPathComponent("system-0001.m4a")

        try finalizeSegmentIfUsable(from: micSegmentURL, to: micURL)
        if runtimeSettings.systemAudioEnabled {
            try finalizeSegmentIfUsable(from: systemSegmentURL, to: systemURL)
        }

        var audioTracks: [AudioTrackMetadata] = []
        audioTracks.append(
            await sourceTrackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                url: micURL,
                fallbackDuration: duration,
                sampleRate: AVFoundationMicrophoneRecordingController.sampleRate,
                channels: AVFoundationMicrophoneRecordingController.channels,
                bitrate: runtimeSettings.audioQualityPreset.microphoneBitrate
            )
        )
        if runtimeSettings.systemAudioEnabled {
            audioTracks.append(
                await sourceTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    url: systemURL,
                    fallbackDuration: systemResult?.successValue?.duration ?? duration,
                    sampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
                    channels: ScreenCaptureKitSystemAudioRecorder.channels,
                    bitrate: runtimeSettings.audioQualityPreset.systemAudioBitrate,
                    error: systemResult?.failureDescription
                )
            )
        } else {
            audioTracks.append(
                AudioTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    codec: "aac",
                    container: "m4a",
                    sampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
                    channels: ScreenCaptureKitSystemAudioRecorder.channels,
                    bitrate: runtimeSettings.audioQualityPreset.systemAudioBitrate,
                    status: "disabled",
                    error: "system audio disabled in settings"
                )
            )
        }

        let sessionStatus: TaggingStatus
        var recoveryError: String?
        if !runtimeSettings.mixedPreviewEnabled {
            audioTracks.append(
                AudioTrackMetadata(
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
            )
            sessionStatus = TaggingStatus.finalizedStatus(
                forDuration: duration,
                preferredStatus: .needsTagging,
                thresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
            )
        } else {
            do {
                let mixedResult = try await mixedAudioPreviewGenerator.createPreview(
                    micURL: micURL,
                    systemURL: systemURL,
                    outputURL: mixedURL,
                    qualityPreset: runtimeSettings.audioQualityPreset
                )
                audioTracks.append(mixedResult.track)
                sessionStatus = TaggingStatus.finalizedStatus(
                    forDuration: duration,
                    preferredStatus: .needsTagging,
                    thresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
                )
            } catch RecordingControllerError.mixedAudioNoSourceTracks {
                AppLogger.file(.error, category: "recording", "mixed audio preview failed no source tracks output=\(mixedURL.path(percentEncoded: false))")
                audioTracks.append(
                    AudioTrackMetadata(
                        kind: "mixed",
                        relativePath: "export/mixed.m4a",
                        codec: "aac",
                        container: "m4a",
                        sampleRate: MixedAudioPreviewGenerator.sampleRate,
                        channels: MixedAudioPreviewGenerator.channels,
                        bitrate: runtimeSettings.audioQualityPreset.mixedPreviewBitrate,
                        status: "failed",
                        error: RecordingControllerError.mixedAudioNoSourceTracks.description
                    )
                )
                sessionStatus = .failed
                recoveryError = RecordingControllerError.mixedAudioNoSourceTracks.description
            } catch {
                AppLogger.recording.error("Mixed audio preview failed: \(String(describing: error), privacy: .public)")
                AppLogger.file(.error, category: "recording", "mixed audio preview failed error=\(String(describing: error)) output=\(mixedURL.path(percentEncoded: false))")
                audioTracks.append(
                    AudioTrackMetadata(
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
                )
                sessionStatus = .failed
                recoveryError = String(describing: error)
            }
        }

        try updateRecoveryMetadata(
            for: activeSession,
            status: sessionStatus == .failed ? .failed : .completed,
            error: recoveryError
        )

        let draft = try store.stopSession(
            activeSession,
            endedAt: endedAt,
            duration: duration,
            status: sessionStatus,
            audioTracks: audioTracks,
            shortRecordingThresholdSeconds: runtimeSettings.shortRecordingThresholdSeconds
        )

        AppLogger.recording.info("Microphone and system audio recording stopped after \(duration, privacy: .public) seconds")
        AppLogger.file(.info, category: "recording", "recording files finalized duration=\(duration) mic=\(micURL.path(percentEncoded: false)) system=\(systemURL.path(percentEncoded: false)) mixed=\(mixedURL.path(percentEncoded: false))")

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration,
            postCallDraft: draft
        )
    }

    public func currentAudioLevels() -> AudioLevelSnapshot {
        var microphoneLevel: Float = 0
        if let microphoneRecorder, microphoneRecorder.isRecording {
            microphoneRecorder.updateMeters()
            microphoneLevel = Self.normalizedLevel(
                fromAveragePower: microphoneRecorder.averagePower(forChannel: 0)
            )
        }

        return AudioLevelSnapshot(
            microphoneLevel: microphoneLevel,
            systemAudioLevel: systemAudioRecorder?.currentLevel() ?? 0
        )
    }

    private func ensureMicrophonePermission() async throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .denied, .restricted:
            AppLogger.file(.error, category: "permissions", "microphone permission denied or restricted")
            throw RecordingControllerError.microphonePermissionDenied
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            guard granted else {
                AppLogger.file(.error, category: "permissions", "microphone permission request denied")
                throw RecordingControllerError.microphonePermissionDenied
            }
        @unknown default:
            AppLogger.file(.error, category: "permissions", "microphone permission unknown authorization state")
            throw RecordingControllerError.microphonePermissionDenied
        }
    }

    private func selectMicrophoneInput(settings: RecordingRuntimeSettings) throws -> MicrophoneDeviceSelection {
        let devices = MicrophoneDeviceProvider.availableInputDevices()
        guard let selection = DevicePriorityResolver.resolve(
            devices: devices,
            preferredDeviceID: settings.preferredMicrophoneDeviceID
        ) else {
            AppLogger.file(.error, category: "recording", "no microphone input device available")
            throw RecordingControllerError.noInputDevice
        }

        #if canImport(CoreAudio)
        microphoneInputOverride = try CoreAudioInputDeviceOverride(selectedDeviceUID: selection.device.id)
        #endif
        return selection
    }

    private func sourceTrackMetadata(
        kind: String,
        relativePath: String,
        url: URL,
        fallbackDuration: TimeInterval,
        sampleRate: Double,
        channels: Int,
        bitrate: Int,
        error: String? = nil
    ) async -> AudioTrackMetadata {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            AppLogger.file(.error, category: "recording", "missing \(kind) audio file path=\(path)")
            return AudioTrackMetadata(
                kind: kind,
                relativePath: relativePath,
                codec: "aac",
                container: "m4a",
                durationSec: nil,
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                status: "failed",
                error: error ?? "Missing \(kind) file at \(path)"
            )
        }

        do {
            let fileSize = try recordedFileSize(at: url, kind: kind)
            return AudioTrackMetadata(
                kind: kind,
                relativePath: relativePath,
                codec: "aac",
                container: "m4a",
                durationSec: await detectedDuration(at: url, fallback: fallbackDuration),
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                fileSizeBytes: fileSize,
                status: error == nil ? "completed" : "failed",
                signal: error == nil ? AudioSignalAnalyzer.analyze(url: url) : nil,
                error: error
            )
        } catch {
            AppLogger.file(.error, category: "recording", "\(kind) audio file failed integrity check path=\(path) error=\(String(describing: error))")
            return AudioTrackMetadata(
                kind: kind,
                relativePath: relativePath,
                codec: "aac",
                container: "m4a",
                durationSec: nil,
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                status: "failed",
                error: String(describing: error)
            )
        }
    }

    private func detectedDuration(at url: URL, fallback: TimeInterval) async -> TimeInterval {
        do {
            let duration = try await AVURLAsset(url: url).load(.duration)
            guard duration.isNumeric else {
                return fallback
            }
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : fallback
        } catch {
            AppLogger.recording.error("Failed to detect audio duration: \(url.path(percentEncoded: false), privacy: .public), error=\(String(describing: error), privacy: .public)")
            return fallback
        }
    }

    private func recordedFileSize(at url: URL, kind: String) throws -> Int64 {
        let path = url.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        let size = attributes[.size] as? NSNumber
        guard let size, size.int64Value > 0 else {
            throw RecordingControllerError.fileWriteFailed("Empty \(kind) file at \(path)")
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

        recovery.status = status
        recovery.updatedAt = iso8601(Date())
        recovery.error = error
        let updatedAt = recovery.updatedAt
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
        microphoneRecorder = nil
        systemAudioRecorder = nil
        microphoneInputOverride?.restore()
        microphoneInputOverride = nil
        selectedMicrophoneDevice = nil
        runtimeSettings = RecordingRuntimeSettings()
    }

    nonisolated public func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        if let error {
            AppLogger.recording.error("Microphone recorder encode error: \(String(describing: error), privacy: .public)")
        }
    }
}

private extension MacOSAudioRecordingController {
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

private extension Result where Success == SystemAudioRecordingResult, Failure == Error {
    var successValue: SystemAudioRecordingResult? {
        guard case .success(let value) = self else {
            return nil
        }
        return value
    }

    var failureDescription: String? {
        guard case .failure(let error) = self else {
            return nil
        }
        return String(describing: error)
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
