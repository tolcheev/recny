import Foundation
import Testing
@testable import TOrbitRecorderCore

struct AudioTrimExporterTests {
    @Test
    func exportsNonDestructiveClipFromAudioFile() async throws {
        let root = Self.testOutputFolder()
        let outputURL = RecordingDerivedArtifactPaths.trimmedAudioURL(
            sessionFolderURL: root,
            date: Date(timeIntervalSince1970: 0)
        )
        let sourceURL = Self.fixtureAudioURL()
        let sourceDuration = try await AudioTrimExporter.audioDuration(of: sourceURL)
        let clipEnd = max(0.08, sourceDuration / 2)

        let result = try await AudioTrimExporter().exportClip(
            sourceURL: sourceURL,
            outputURL: outputURL,
            startSeconds: 0,
            endSeconds: clipEnd
        )

        #expect(result.outputURL == outputURL)
        #expect(result.sourceURL == sourceURL)
        #expect(result.durationSec > 0)
        #expect(result.durationSec <= sourceDuration)
        #expect(result.fileSizeBytes > 0)
        #expect(FileManager.default.fileExists(atPath: outputURL.path(percentEncoded: false)))
    }

    @Test
    func rejectsInvalidTrimRange() async throws {
        await #expect(throws: AudioTrimError.invalidRange) {
            try await AudioTrimExporter().exportClip(
                sourceURL: Self.fixtureAudioURL(),
                outputURL: Self.testOutputFolder().appendingPathComponent("export/clip.m4a"),
                startSeconds: 2,
                endSeconds: 1
            )
        }
    }

    private static func fixtureAudioURL() -> URL {
        URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
    }

    private static func testOutputFolder() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("audio-trim-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
