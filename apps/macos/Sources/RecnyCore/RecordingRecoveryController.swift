@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

public final class RecordingRecoveryController: @unchecked Sendable {
    private let store: FileSystemRecordingStore
    private let mixedAudioPreviewGenerator: MixedAudioPreviewGenerator

    public init(
        store: FileSystemRecordingStore,
        mixedAudioPreviewGenerator: MixedAudioPreviewGenerator = MixedAudioPreviewGenerator()
    ) {
        self.store = store
        self.mixedAudioPreviewGenerator = mixedAudioPreviewGenerator
    }

    public func recover(_ summary: RecoverableRecordingSummary) async throws -> PostCallDraft {
        var recovery = try store.readRecoveryMetadata(at: summary.recoveryMetadataURL)
        let startedAt = parseISO8601(recovery.startedAt) ?? Date()
        let endedAt = Date()
        let session = RecordingSession(
            id: recovery.recordingID,
            startedAt: startedAt,
            source: recovery.source,
            folderURL: summary.folderURL
        )

        let micURL = session.sourceURL.appendingPathComponent("mic.m4a")
        let systemURL = session.sourceURL.appendingPathComponent("system.m4a")
        let mixedURL = session.exportURL.appendingPathComponent("mixed.m4a")

        try finalizeFirstSegment(
            prefix: "mic-",
            from: session.segmentsURL,
            to: micURL
        )
        try finalizeFirstSegment(
            prefix: "system-",
            from: session.segmentsURL,
            to: systemURL
        )

        var audioTracks: [AudioTrackMetadata] = []
        audioTracks.append(
            await trackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                url: micURL,
                sampleRate: AVFoundationMicrophoneRecordingController.sampleRate,
                channels: AVFoundationMicrophoneRecordingController.channels,
                bitrate: AVFoundationMicrophoneRecordingController.bitrate
            )
        )
        audioTracks.append(
            await trackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                url: systemURL,
                sampleRate: ScreenCaptureKitSystemAudioRecorder.sampleRate,
                channels: ScreenCaptureKitSystemAudioRecorder.channels,
                bitrate: ScreenCaptureKitSystemAudioRecorder.bitrate
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
            recovery.status = .recovered
            recovery.error = nil
            sessionStatus = .needsReview
        } catch {
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
            recovery.status = .failed
            recovery.error = String(describing: error)
            sessionStatus = .failed
        }

        recovery.updatedAt = iso8601(endedAt)
        recovery.segments = recovery.segments.map { segment in
            var updated = segment
            let url = session.folderURL.appendingPathComponent(segment.relativePath)
            let size = fileSize(at: url)
            updated.fileSizeBytes = size
            updated.status = (size ?? 0) > 0 ? "preserved" : "missing"
            updated.updatedAt = recovery.updatedAt
            return updated
        }
        try store.writeRecoveryMetadata(recovery, to: session.recoveryMetadataURL)

        let duration = max(0, endedAt.timeIntervalSince(startedAt))
        return try store.stopSession(
            session,
            endedAt: endedAt,
            duration: duration,
            status: sessionStatus,
            audioTracks: audioTracks
        )
    }

    private func finalizeFirstSegment(prefix: String, from segmentsURL: URL, to finalURL: URL) throws {
        guard FileManager.default.fileExists(atPath: segmentsURL.path(percentEncoded: false)) else {
            return
        }

        let candidates = try FileManager.default.contentsOfDirectory(
            at: segmentsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            url.lastPathComponent.hasPrefix(prefix) && ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }

        guard let segmentURL = candidates.first else {
            return
        }

        try FileManager.default.removeItemIfExists(at: finalURL)
        try FileManager.default.copyItem(at: segmentURL, to: finalURL)
    }

    private func trackMetadata(
        kind: String,
        relativePath: String,
        url: URL,
        sampleRate: Double,
        channels: Int,
        bitrate: Int
    ) async -> AudioTrackMetadata {
        guard let size = fileSize(at: url), size > 0 else {
            return AudioTrackMetadata(
                kind: kind,
                relativePath: relativePath,
                codec: "aac",
                container: "m4a",
                sampleRate: sampleRate,
                channels: channels,
                bitrate: bitrate,
                status: "failed",
                error: "Recovered source file is missing or empty"
            )
        }

        return AudioTrackMetadata(
            kind: kind,
            relativePath: relativePath,
            codec: "aac",
            container: "m4a",
            durationSec: await duration(at: url),
            sampleRate: sampleRate,
            channels: channels,
            bitrate: bitrate,
            fileSizeBytes: size,
            status: "completed",
            signal: AudioSignalAnalyzer.analyze(url: url)
        )
    }

    private func duration(at url: URL) async -> TimeInterval? {
        do {
            let duration = try await AVURLAsset(url: url).load(.duration)
            guard duration.isNumeric else {
                return nil
            }
            let seconds = CMTimeGetSeconds(duration)
            return seconds.isFinite && seconds > 0 ? seconds : nil
        } catch {
            return nil
        }
    }

    private func fileSize(at url: URL) -> Int64? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false))
        return (attributes?[.size] as? NSNumber)?.int64Value
    }

    private func parseISO8601(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value)
    }

    private func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
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
