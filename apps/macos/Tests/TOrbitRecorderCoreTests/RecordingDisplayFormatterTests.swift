import Testing
@testable import TOrbitRecorderCore

struct RecordingDisplayFormatterTests {
    @Test
    func mapsRawStatusesToHumanReadableCopy() {
        #expect(RecordingDisplayFormatter.statusText(.needsTagging) == "Needs tag")
        #expect(RecordingDisplayFormatter.statusText(.saved) == "Saved")
        #expect(RecordingDisplayFormatter.statusText(.shortRecording) == "Short recording")
        #expect(RecordingDisplayFormatter.statusText(.failed) == "Recording failed")
    }

    @Test
    func formatsDurationForRecorderUi() {
        #expect(RecordingDisplayFormatter.duration(0) == "00:00")
        #expect(RecordingDisplayFormatter.duration(75) == "01:15")
        #expect(RecordingDisplayFormatter.duration(3_661) == "1:01:01")
    }

    @Test
    func formatsMarkerTimestamps() {
        #expect(RecordingDisplayFormatter.markerTimestamp(0) == "00:00")
        #expect(RecordingDisplayFormatter.markerTimestamp(123) == "02:03")
        #expect(RecordingDisplayFormatter.markerTimestamp(3_661) == "1:01:01")
    }

    @Test
    func formatsFileSizesCompactly() {
        #expect(RecordingDisplayFormatter.fileSize(nil) == "Missing")
        #expect(RecordingDisplayFormatter.fileSize(0) == "Missing")
        #expect(RecordingDisplayFormatter.fileSize(13_312) == "13 KB")
        #expect(RecordingDisplayFormatter.fileSize(1_572_864) == "1.5 MB")
    }

    @Test
    func summarizesAvailableAudioSides() {
        #expect(RecordingDisplayFormatter.audioSummary(micFileSizeBytes: 10, systemFileSizeBytes: 20) == "Mic + system audio")
        #expect(RecordingDisplayFormatter.audioSummary(micFileSizeBytes: 10, systemFileSizeBytes: nil) == "Mic only")
        #expect(RecordingDisplayFormatter.audioSummary(micFileSizeBytes: nil, systemFileSizeBytes: 20) == "System only")
        #expect(RecordingDisplayFormatter.audioSummary(micFileSizeBytes: nil, systemFileSizeBytes: nil) == "No audio")
    }

    @Test
    func keepsMicrophoneDisplayHumanReadable() {
        #expect(RecordingDisplayFormatter.microphoneName("MacBook Pro Microphone") == "MacBook Pro Microphone")
        #expect(RecordingDisplayFormatter.microphoneName("  ") == "No microphone selected")
    }

    @Test
    func exposesShortRecordingCopy() {
        #expect(RecordingDisplayFormatter.statusSubtitle(.shortRecording) == "Saved to Inbox/Short")
    }

    @Test
    func formatsLatestRecordingStripWithoutDebugFields() {
        #expect(
            RecordingDisplayFormatter.latestStripSummary(
                status: .shortRecording,
                duration: 8,
                micFileSizeBytes: 10,
                systemFileSizeBytes: 20
            ) == "Last: Short recording · 00:08 · Mic + system"
        )
    }

    @Test
    func explainsSystemAudioPermissionRestartCase() {
        #expect(
            RecordingDisplayFormatter.humanReadableError(
                "Screen & System Audio Recording permission is unavailable: SCStreamErrorDomain code -3801"
            ) == "System audio permission needs app restart or re-approval"
        )
    }
}
