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

    @Test
    func formatsPlaybackStateWithoutRawTechnicalStatuses() {
        #expect(RecordingDisplayFormatter.playbackStateText(.balancedReady) == "Audio: Balanced")
        #expect(RecordingDisplayFormatter.playbackStateText(.originalOnly) == "Audio: Original")
        #expect(RecordingDisplayFormatter.playbackStateText(.balancedFailed) == "Audio: Balanced failed")
        #expect(RecordingDisplayFormatter.audioProcessingCopy(state: .balancedReady) == "Balanced audio ready")
        #expect(RecordingDisplayFormatter.audioProcessingCopy(state: .levelingSkipped) == "Audio leveling skipped")
        #expect(RecordingDisplayFormatter.audioProcessingCopy(state: .balancedFailed) == "Audio leveling failed")
    }

    @Test
    func formatsAudioHealthForUserFacingUi() {
        #expect(RecordingDisplayFormatter.audioHealthBadgeText(.good) == "Audio OK")
        #expect(RecordingDisplayFormatter.audioHealthBadgeText(.warning) == "Audio warning")
        #expect(RecordingDisplayFormatter.audioHealthBadgeText(.failed) == "Audio failed")

        #expect(
            RecordingDisplayFormatter.audioHealthWarningText(.micTooQuiet) == "Microphone seems too quiet"
        )
        #expect(
            RecordingDisplayFormatter.audioHealthWarningText(.balancedMixFailed) == "Balanced mix failed, original audio is available"
        )
        #expect(
            RecordingDisplayFormatter.audioHealthSuccessText(processingStatus: .done) == "Balanced mix was created"
        )
    }
}
