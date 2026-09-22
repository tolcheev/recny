import Foundation
import Testing
@testable import RecnyCore

struct RecordingPlaybackResolverTests {
    @Test
    func prefersBalancedMixWhenItExistsAndIsNonEmpty() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 12, to: folder.appendingPathComponent("export/mixed.m4a"))
        try write(bytes: 20, to: folder.appendingPathComponent("export/mixed_balanced.m4a"))

        let playback = try #require(
            RecordingPlaybackResolver.preferredPlayback(
                sessionFolderURL: folder,
                processingStatus: .done
            )
        )

        #expect(playback.kind == .balanced)
        #expect(playback.url.lastPathComponent == "mixed_balanced.m4a")
    }

    @Test
    func fallsBackToOriginalWhenBalancedIsMissing() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 12, to: folder.appendingPathComponent("export/mixed.m4a"))

        let playback = try #require(
            RecordingPlaybackResolver.preferredPlayback(
                sessionFolderURL: folder,
                processingStatus: .failed
            )
        )

        #expect(playback.kind == .original)
        #expect(playback.url.lastPathComponent == "mixed.m4a")
        #expect(
            RecordingPlaybackResolver.displayState(
                sessionFolderURL: folder,
                processingStatus: .failed
            ) == .balancedFailed
        )
    }

    @Test
    func fallsBackToSourceTrackWhenMixesAreMissing() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 12, to: folder.appendingPathComponent("source/mic.m4a"))

        let playback = try #require(
            RecordingPlaybackResolver.preferredPlayback(
                sessionFolderURL: folder,
                processingStatus: .skipped
            )
        )

        #expect(playback.kind == .microphone)
        #expect(playback.url.lastPathComponent == "mic.m4a")
    }

    @Test
    func failedLevelingShowsWarningEvenWhenOnlySourceFallbackExists() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 12, to: folder.appendingPathComponent("source/mic.m4a"))

        #expect(
            RecordingPlaybackResolver.displayState(
                sessionFolderURL: folder,
                processingStatus: .failed
            ) == .balancedFailed
        )
    }

    @Test
    func ignoresEmptyBalancedMix() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 12, to: folder.appendingPathComponent("export/mixed.m4a"))
        try write(bytes: 0, to: folder.appendingPathComponent("export/mixed_balanced.m4a"))

        let playback = try #require(
            RecordingPlaybackResolver.preferredPlayback(
                sessionFolderURL: folder,
                processingStatus: .done
            )
        )

        #expect(playback.kind == .original)
    }

    @Test
    func inlinePlaybackRequestUsesReadableTitleAndStableIdentity() throws {
        let folder = try makeRecordingFolder()
        let url = folder.appendingPathComponent("export/mixed_balanced.m4a")
        try write(bytes: 20, to: url)
        let candidate = RecordingPlaybackCandidate(kind: .balanced, url: url, fileSizeBytes: 20)

        let request = RecordingInlinePlaybackRequest(
            recordingID: "rec_123",
            recordingTitle: "Screening call",
            candidate: candidate
        )

        #expect(request.id == "rec_123|\(url.path(percentEncoded: false))")
        #expect(request.recordingID == "rec_123")
        #expect(request.title == "Screening call - Balanced")
        #expect(request.kind == .balanced)
        #expect(request.url == url)
    }

    @Test
    func deletionStopsInlinePlaybackForDeletedRecording() throws {
        let folder = try makeRecordingFolder()
        let url = folder.appendingPathComponent("export/mixed_balanced.m4a")
        let candidate = RecordingPlaybackCandidate(kind: .balanced, url: url, fileSizeBytes: 20)
        let request = RecordingInlinePlaybackRequest(
            recordingID: "rec_123",
            recordingTitle: "Screening call",
            candidate: candidate
        )

        #expect(
            RecordingPlaybackResolver.shouldStopPlaybackBeforeDeleting(
                inlinePlayback: request,
                deletedRecordingID: "rec_123",
                deletedSessionFolderURL: folder
            )
        )
    }

    @Test
    func deletionDoesNotStopInlinePlaybackForDifferentRecordingOutsideDeletedFolder() throws {
        let deletedFolder = try makeRecordingFolder()
        let otherFolder = try makeRecordingFolder()
        let url = otherFolder.appendingPathComponent("export/mixed_balanced.m4a")
        let candidate = RecordingPlaybackCandidate(kind: .balanced, url: url, fileSizeBytes: 20)
        let request = RecordingInlinePlaybackRequest(
            recordingID: "rec_other",
            recordingTitle: "Other call",
            candidate: candidate
        )

        #expect(
            !RecordingPlaybackResolver.shouldStopPlaybackBeforeDeleting(
                inlinePlayback: request,
                deletedRecordingID: "rec_123",
                deletedSessionFolderURL: deletedFolder
            )
        )
    }

    @Test
    func externalPlayerURLIsMatchedOnlyInsideDeletedSessionFolder() throws {
        let folder = try makeRecordingFolder()
        let siblingFolder = folder
            .deletingLastPathComponent()
            .appendingPathComponent("\(folder.lastPathComponent)-copy", isDirectory: true)
        let playbackURL = folder.appendingPathComponent("export/mixed.m4a")
        let siblingURL = siblingFolder.appendingPathComponent("export/mixed.m4a")

        #expect(RecordingPlaybackResolver.isPlaybackURL(playbackURL, insideSessionFolder: folder))
        #expect(!RecordingPlaybackResolver.isPlaybackURL(siblingURL, insideSessionFolder: folder))
        #expect(!RecordingPlaybackResolver.isPlaybackURL(nil, insideSessionFolder: folder))
    }

    @Test
    func shareableAudioPrefersBalancedThenOriginalThenSourceTrack() throws {
        let folder = try makeRecordingFolder()
        let mixedURL = folder.appendingPathComponent("export/mixed.m4a")
        let balancedURL = folder.appendingPathComponent("export/mixed_balanced.m4a")
        let micURL = folder.appendingPathComponent("source/mic.m4a")

        try write(bytes: 8, to: micURL)
        var shareable = try #require(RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: folder))
        #expect(shareable.kind == .microphone)
        #expect(shareable.url == micURL)

        try write(bytes: 12, to: mixedURL)
        shareable = try #require(RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: folder))
        #expect(shareable.kind == .original)
        #expect(shareable.url == mixedURL)

        try write(bytes: 20, to: balancedURL)
        shareable = try #require(RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: folder))
        #expect(shareable.kind == .balanced)
        #expect(shareable.url == balancedURL)
    }

    @Test
    func shareableAudioReturnsNilWhenAllAudioFilesAreMissingOrEmpty() throws {
        let folder = try makeRecordingFolder()
        try write(bytes: 0, to: folder.appendingPathComponent("export/mixed.m4a"))
        try write(bytes: 0, to: folder.appendingPathComponent("source/mic.m4a"))

        #expect(RecordingPlaybackResolver.preferredShareableAudio(sessionFolderURL: folder) == nil)
    }

    @Test
    func userFacingShareableAudioCreatesReadableDatedCopy() throws {
        let folder = try makeRecordingFolder()
        let balancedURL = folder.appendingPathComponent("export/mixed_balanced.m4a")
        try write(bytes: 20, to: balancedURL)

        let recording = RecordingSummary(
            id: "rec_2026-06-09_13-13",
            title: "Wildberries",
            category: "",
            participant: "",
            tags: [],
            status: .saved,
            sourceApp: "Zoom",
            startedAt: "2026-06-09T13:13:00.000Z",
            endedAt: "2026-06-09T13:33:00.000Z",
            durationSec: 1_305,
            metadataURL: folder.appendingPathComponent("metadata.json"),
            sessionFolderURL: folder
        )

        let shareable = try #require(try RecordingPlaybackResolver.preferredUserFacingShareableAudio(for: recording))

        #expect(shareable.kind == .balanced)
        #expect(shareable.url.deletingLastPathComponent().lastPathComponent == "share")
        #expect(shareable.url.lastPathComponent == "wildberries_09_06_26.m4a")
        #expect(RecordingPlaybackResolver.nonEmptyFileSize(at: shareable.url) == 20)
        #expect(shareable.url != balancedURL)
        #expect(RecordingPlaybackResolver.nonEmptyFileSize(at: balancedURL) == 20)
    }

    @Test
    func userFacingShareableAudioFallsBackToDatedRecordingName() throws {
        let folder = try makeRecordingFolder()
        let mixedURL = folder.appendingPathComponent("export/mixed.m4a")
        try write(bytes: 12, to: mixedURL)

        let recording = RecordingSummary(
            id: "rec_2026-06-09_13-13",
            title: "  ",
            category: "",
            participant: "",
            tags: [],
            status: .saved,
            sourceApp: "Zoom",
            startedAt: "2026-06-09 13:13",
            endedAt: "2026-06-09 13:33",
            durationSec: 1_305,
            metadataURL: folder.appendingPathComponent("metadata.json"),
            sessionFolderURL: folder
        )

        let shareable = try #require(try RecordingPlaybackResolver.preferredUserFacingShareableAudio(for: recording))

        #expect(shareable.kind == .original)
        #expect(shareable.url.lastPathComponent == "recording_09_06_26.m4a")
        #expect(RecordingPlaybackResolver.nonEmptyFileSize(at: shareable.url) == 12)
    }

    private func makeRecordingFolder() throws -> URL {
        let folder = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("playback-resolver-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("source", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: folder.appendingPathComponent("export", isDirectory: true),
            withIntermediateDirectories: true
        )
        return folder
    }

    private func write(bytes count: Int, to url: URL) throws {
        let data = Data(repeating: 1, count: count)
        try data.write(to: url)
    }
}
