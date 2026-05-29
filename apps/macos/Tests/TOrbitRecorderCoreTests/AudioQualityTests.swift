import Testing
@testable import TOrbitRecorderCore

struct AudioQualityTests {
    @Test
    func presetsMapToSpeechRecordingBitrates() {
        #expect(AudioQualityPreset.compact.microphoneBitrate == 96_000)
        #expect(AudioQualityPreset.compact.systemAudioBitrate == 96_000)
        #expect(AudioQualityPreset.compact.mixedPreviewBitrate == 80_000)

        #expect(AudioQualityPreset.standard.microphoneBitrate == 128_000)
        #expect(AudioQualityPreset.standard.systemAudioBitrate == 128_000)
        #expect(AudioQualityPreset.standard.mixedPreviewBitrate == 96_000)

        #expect(AudioQualityPreset.high.microphoneBitrate == 192_000)
        #expect(AudioQualityPreset.high.systemAudioBitrate == 192_000)
        #expect(AudioQualityPreset.high.mixedPreviewBitrate == 128_000)
    }

    @Test
    func mapsSignalMetadataToUserWarnings() {
        let tracks = [
            AudioTrackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                status: "completed",
                signal: AudioSignalMetadata(
                    hadSignal: false,
                    approximateSilenceRatio: 0.99,
                    clippingDetected: true
                )
            ),
            AudioTrackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                status: "completed",
                signal: AudioSignalMetadata(
                    hadSignal: false,
                    approximateSilenceRatio: 0.97,
                    clippingDetected: false
                )
            )
        ]

        #expect(AudioQualityWarningMapper.warnings(for: tracks) == [
            "Microphone track seems silent.",
            "System audio track seems silent.",
            "Microphone is clipping."
        ])
    }

    @Test
    func mapsCompletedWithWarningsSignalMetadataToUserWarnings() {
        let tracks = [
            AudioTrackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                fileSizeBytes: 160_000,
                status: "completed_with_warnings",
                signal: AudioSignalMetadata(
                    hadSignal: false,
                    approximateSilenceRatio: 0.98,
                    clippingDetected: false
                ),
                error: "Recorder stop returned a late CoreAudio warning."
            )
        ]

        #expect(AudioQualityWarningMapper.warnings(for: tracks) == [
            "System audio track seems silent."
        ])
    }

    @Test
    func mapsTruncatedSystemTrackToUserWarning() {
        let tracks = [
            AudioTrackMetadata(
                kind: "microphone",
                relativePath: "source/mic.m4a",
                durationSec: 420,
                fileSizeBytes: 420_000,
                status: "completed",
                signal: AudioSignalMetadata(
                    hadSignal: true,
                    approximateSilenceRatio: 0.2,
                    clippingDetected: false
                )
            ),
            AudioTrackMetadata(
                kind: "system",
                relativePath: "source/system.m4a",
                durationSec: 170,
                fileSizeBytes: 170_000,
                status: "completed_with_warnings",
                signal: AudioSignalMetadata(
                    hadSignal: true,
                    approximateSilenceRatio: 0.3,
                    clippingDetected: false
                ),
                error: "Core Audio writer stopped early."
            )
        ]

        #expect(AudioQualityWarningMapper.warnings(for: tracks, recordingDuration: 420) == [
            "System audio track ended before the recording stopped."
        ])
    }

    @Test
    func recordingMetadataStoresQualityWarnings() {
        let metadata = RecordingMetadata(
            id: "rec_quality",
            title: "Quality check",
            startedAt: "2026-05-24T00:00:00Z",
            endedAt: "2026-05-24T00:01:00Z",
            durationSec: 60,
            qualityWarnings: [
                "Microphone track seems silent.",
                "System audio track seems silent."
            ]
        )

        #expect(metadata.qualityWarnings == [
            "Microphone track seems silent.",
            "System audio track seems silent."
        ])
    }
}
