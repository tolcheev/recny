import Foundation
import Testing
@testable import TOrbitRecorderCore

struct AudioHealthTests {
    @Test
    func goodWhenBothTracksHaveSignalAndBalancedMixIsReady() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.completedTrack(kind: "microphone", size: 120_000, hadSignal: true),
                Self.completedTrack(kind: "system", size: 160_000, hadSignal: true)
            ],
            processing: AudioProcessingMetadata(balancedMixStatus: .done)
        )

        #expect(health.status == .good)
        #expect(health.warnings.isEmpty)
    }

    @Test
    func mapsSilentAndClippingSignalsToWarnings() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.completedTrack(kind: "microphone", size: 120_000, hadSignal: false, silenceRatio: 0.99, clipping: true),
                Self.completedTrack(kind: "system", size: 160_000, hadSignal: false, silenceRatio: 0.97)
            ],
            processing: .skipped
        )

        #expect(health.status == .warning)
        #expect(health.warnings == [.micSilent, .systemSilent, .clippingDetected])
    }

    @Test
    func mapsQuietAnalysisToWarningsWithoutCallingItSilent() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.completedTrack(kind: "microphone", size: 120_000, hadSignal: true, silenceRatio: 0.3),
                Self.completedTrack(kind: "system", size: 160_000, hadSignal: true, silenceRatio: 0.2)
            ],
            processing: .skipped,
            microphoneAnalysis: Self.analysis(kind: .microphone, loudness: -47, hasUsableSignal: true),
            systemAnalysis: Self.analysis(kind: .system, loudness: -46, hasUsableSignal: true)
        )

        #expect(health.status == .warning)
        #expect(health.warnings == [.micTooQuiet, .systemTooQuiet])
    }

    @Test
    func balancedMixFailureIsAWarningWhenOriginalAudioExists() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.completedTrack(kind: "microphone", size: 120_000, hadSignal: true),
                Self.completedTrack(kind: "system", size: 160_000, hadSignal: true),
                Self.failedTrack(kind: "mixed_balanced")
            ],
            processing: AudioProcessingMetadata(balancedMixStatus: .failed)
        )

        #expect(health.status == .warning)
        #expect(health.warnings == [.balancedMixFailed])
    }

    @Test
    func onlyOneAvailableTrackCreatesWarning() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.completedTrack(kind: "microphone", size: 120_000, hadSignal: true),
                Self.failedTrack(kind: "system")
            ],
            processing: .skipped
        )

        #expect(health.status == .warning)
        #expect(health.warnings == [.onlyOneTrackAvailable])
    }

    @Test
    func noUsableSourceTracksIsFailed() {
        let health = AudioHealthEvaluator.evaluate(
            audioTracks: [
                Self.failedTrack(kind: "microphone"),
                Self.failedTrack(kind: "system")
            ],
            processing: AudioProcessingMetadata(balancedMixStatus: .failed)
        )

        #expect(health.status == .failed)
        #expect(health.warnings.contains(.balancedMixFailed))
        #expect(health.warnings.contains(.onlyOneTrackAvailable) == false)
    }

    @Test
    func recordingMetadataPersistsAudioHealth() throws {
        let metadata = RecordingMetadata(
            id: "rec_health",
            title: "Audio health check",
            startedAt: "2026-05-24T00:00:00Z",
            endedAt: "2026-05-24T00:01:00Z",
            durationSec: 60,
            audio: RecordingAudioMetadata(
                processing: AudioProcessingMetadata(balancedMixStatus: .failed),
                health: AudioHealthMetadata(
                    status: .warning,
                    warnings: [.micTooQuiet, .balancedMixFailed]
                )
            )
        )

        let codec = RecordingMetadataCodec()
        let data = try codec.encode(metadata)
        let decoded = try codec.decode(data)

        #expect(decoded.audio.health.status == .warning)
        #expect(decoded.audio.health.warnings == [.micTooQuiet, .balancedMixFailed])
    }

    private static func completedTrack(
        kind: String,
        size: Int64,
        hadSignal: Bool,
        silenceRatio: Double = 0.1,
        clipping: Bool = false
    ) -> AudioTrackMetadata {
        AudioTrackMetadata(
            kind: kind,
            relativePath: kind == "system" ? "source/system.m4a" : "source/mic.m4a",
            fileSizeBytes: size,
            status: "completed",
            signal: AudioSignalMetadata(
                hadSignal: hadSignal,
                approximateSilenceRatio: silenceRatio,
                clippingDetected: clipping
            )
        )
    }

    private static func failedTrack(kind: String) -> AudioTrackMetadata {
        AudioTrackMetadata(
            kind: kind,
            relativePath: "\(kind).m4a",
            fileSizeBytes: 0,
            status: "failed",
            error: "failed"
        )
    }

    private static func analysis(
        kind: AudioLevelTrackKind,
        loudness: Double,
        hasUsableSignal: Bool
    ) -> AudioLevelAnalysis {
        AudioLevelAnalysis(
            kind: kind,
            relativePath: kind.relativePath,
            exists: true,
            fileSizeBytes: 100_000,
            durationSec: 60,
            peakDBFS: -8,
            rmsDBFS: loudness,
            approximateLoudnessDB: loudness,
            silenceRatio: 0.2,
            clippingDetected: false,
            hasUsableSignal: hasUsableSignal
        )
    }
}
