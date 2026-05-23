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

        let micSegmentURL = session.segmentsURL.appendingPathComponent("mic-0001.m4a")
        let systemSegmentURL = session.segmentsURL.appendingPathComponent("system-0001.m4a")
        let micRecorder = try AVAudioRecorder(
            url: micSegmentURL,
            settings: AVFoundationMicrophoneRecordingController.audioRecorderSettings
        )
        micRecorder.delegate = self

        let systemRecorder = ScreenCaptureKitSystemAudioRecorder()
        try await systemRecorder.start(outputURL: systemSegmentURL)

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
        let micSegmentURL = activeSession.segmentsURL.appendingPathComponent("mic-0001.m4a")
        let systemSegmentURL = activeSession.segmentsURL.appendingPathComponent("system-0001.m4a")

        try finalizeSegmentIfUsable(from: micSegmentURL, to: micURL)
        try finalizeSegmentIfUsable(from: systemSegmentURL, to: systemURL)

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
        var recoveryError: String?
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
            recoveryError = RecordingControllerError.mixedAudioNoSourceTracks.description
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
            recoveryError = String(describing: error)
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

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        if fileExists(atPath: path) {
            try removeItem(at: url)
        }
    }
}
