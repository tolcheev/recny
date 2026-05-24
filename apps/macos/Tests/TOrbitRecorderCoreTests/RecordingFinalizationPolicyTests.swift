import Testing
@testable import TOrbitRecorderCore

struct RecordingFinalizationPolicyTests {
    @Test
    func emptyRequiredSourceTrackFailsRecording() {
        let result = RecordingFinalizationPolicy.finalize(
            duration: 120,
            preferredStatus: .needsTagging,
            shortRecordingThresholdSeconds: 60,
            requiredTrackKinds: ["microphone", "system", "mixed"],
            audioTracks: [
                AudioTrackMetadata(
                    kind: "microphone",
                    relativePath: "source/mic.m4a",
                    fileSizeBytes: 0,
                    status: "failed",
                    error: "Empty audio file"
                ),
                AudioTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    fileSizeBytes: 2048,
                    status: "completed"
                ),
                AudioTrackMetadata(
                    kind: "mixed",
                    relativePath: "export/mixed.m4a",
                    fileSizeBytes: 4096,
                    status: "completed"
                )
            ]
        )

        #expect(result.status == .failed)
        #expect(result.failureReason == "Empty audio file")
    }

    @Test
    func successfulRequiredTracksUseDurationBasedStatus() {
        let result = RecordingFinalizationPolicy.finalize(
            duration: 120,
            preferredStatus: .needsTagging,
            shortRecordingThresholdSeconds: 60,
            requiredTrackKinds: ["microphone", "system", "mixed"],
            audioTracks: [
                AudioTrackMetadata(kind: "microphone", relativePath: "source/mic.m4a", fileSizeBytes: 1024, status: "completed"),
                AudioTrackMetadata(kind: "system", relativePath: "source/system.m4a", fileSizeBytes: 2048, status: "completed"),
                AudioTrackMetadata(kind: "mixed", relativePath: "export/mixed.m4a", fileSizeBytes: 4096, status: "completed")
            ]
        )

        #expect(result.status == .needsTagging)
        #expect(result.failureReason == nil)
    }
}
