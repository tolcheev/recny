import AVFoundation
import Foundation

@MainActor
public final class MacOSAudioRecordingController: NSObject, RecordingController, AVAudioRecorderDelegate {
    private var startedAt: Date?
    private var activeSession: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var microphoneRecorder: AVAudioRecorder?
    private var systemAudioRecorder: ScreenCaptureKitSystemAudioRecorder?
    private let mixedAudioPreviewGenerator: MixedAudioPreviewGenerator

    public override init() {
        self.mixedAudioPreviewGenerator = MixedAudioPreviewGenerator()
        super.init()
    }

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

        let systemResult: Result<SystemAudioRecordingResult, Error>
        do {
            systemResult = .success(try await systemAudioRecorder.stop())
        } catch {
            AppLogger.recording.error("System audio stop failed: \(String(describing: error), privacy: .public)")
            systemResult = .failure(error)
        }

        let endedAt = Date()
        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        let micURL = activeSession.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = activeSession.sourceURL.appendingPathComponent("system.m4a")
        let mixedURL = activeSession.exportURL.appendingPathComponent("mixed.m4a")

        var audioTracks: [AudioTrackMetadata] = []
        audioTracks.append(
            await sourceTrackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                url: micURL,
                fallbackDuration: duration,
                sampleRate: AVFoundationMicrophoneRecordingController.sampleRate,
                channels: AVFoundationMicrophoneRecordingController.channels,
                bitrate: AVFoundationMicrophoneRecordingController.bitrate
            )
        )
        audioTracks.append(
            await sourceTrackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                url: systemURL,
                fallbackDuration: systemResult.successValue?.duration ?? duration,
                sampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
                channels: ScreenCaptureKitSystemAudioRecorder.channels,
                bitrate: ScreenCaptureKitSystemAudioRecorder.bitrate,
                error: systemResult.failureDescription
            )
        )

        let sessionStatus: TaggingStatus
        do {
            let mixedResult = try await mixedAudioPreviewGenerator.createPreview(
                micURL: micURL,
                systemURL: systemURL,
                outputURL: mixedURL
            )
            audioTracks.append(mixedResult.track)
            sessionStatus = .needsTagging
        } catch RecordingControllerError.mixedAudioNoSourceTracks {
            audioTracks.append(
                AudioTrackMetadata(
                    kind: "mixed",
                    relativePath: "export/mixed.m4a",
                    codec: "aac",
                    container: "m4a",
                    sampleRate: MixedAudioPreviewGenerator.sampleRate,
                    channels: MixedAudioPreviewGenerator.channels,
                    bitrate: MixedAudioPreviewGenerator.bitrate,
                    status: "failed",
                    error: RecordingControllerError.mixedAudioNoSourceTracks.description
                )
            )
            sessionStatus = .failed
        } catch {
            AppLogger.recording.error("Mixed audio preview failed: \(String(describing: error), privacy: .public)")
            audioTracks.append(
                AudioTrackMetadata(
                    kind: "mixed",
                    relativePath: "export/mixed.m4a",
                    codec: "aac",
                    container: "m4a",
                    sampleRate: MixedAudioPreviewGenerator.sampleRate,
                    channels: MixedAudioPreviewGenerator.channels,
                    bitrate: MixedAudioPreviewGenerator.bitrate,
                    status: "failed",
                    error: String(describing: error)
                )
            )
            sessionStatus = .failed
        }

        let draft = try store.stopSession(
            activeSession,
            endedAt: endedAt,
            duration: duration,
            status: sessionStatus,
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
                error: error
            )
        } catch {
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
