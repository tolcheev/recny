import Foundation
import Testing
@testable import TOrbitRecorderCore

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
