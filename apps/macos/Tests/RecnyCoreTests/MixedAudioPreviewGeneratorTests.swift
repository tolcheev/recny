import AVFoundation
import Foundation
import Testing
@testable import RecnyCore

struct MixedAudioPreviewGeneratorTests {
    @Test
    func createsMixedPreviewFromSingleAvailableTrack() async throws {
        let root = Self.testOutputFolder()
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let exportURL = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)

        let micURL = sourceURL.appendingPathComponent("mic.aiff")
        let systemURL = sourceURL.appendingPathComponent("system.m4a")
        let mixedURL = exportURL.appendingPathComponent("mixed.m4a")
        try FileManager.default.copyItem(at: Self.fixtureAudioURL(), to: micURL)
        try Data("old mix".utf8).write(to: mixedURL)

        let result = try await MixedAudioPreviewGenerator().createPreview(
            micURL: micURL,
            systemURL: systemURL,
            outputURL: mixedURL
        )

        #expect(FileManager.default.fileExists(atPath: mixedURL.path(percentEncoded: false)))
        #expect(result.fileSizeBytes > 0)
        #expect(result.duration > 0)
        #expect(result.usedSourceKinds == ["microphone"])
        #expect(result.track.kind == "mixed")
        #expect(result.track.relativePath == "export/mixed.m4a")
        #expect(result.track.codec == "aac")
        #expect(result.track.container == "m4a")
        #expect(result.track.sampleRate == 48_000)
        #expect(result.track.bitrate == 96_000)
        #expect(result.track.fileSizeBytes == result.fileSizeBytes)
        #expect(result.track.status == "completed")
    }

    @Test
    func throwsWhenNoSourceTracksAreAvailable() async {
        let root = Self.testOutputFolder()
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let exportURL = root.appendingPathComponent("export", isDirectory: true)
        try? FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)

        await #expect(throws: RecordingControllerError.mixedAudioNoSourceTracks) {
            try await MixedAudioPreviewGenerator().createPreview(
                micURL: sourceURL.appendingPathComponent("mic.m4a"),
                systemURL: sourceURL.appendingPathComponent("system.m4a"),
                outputURL: exportURL.appendingPathComponent("mixed.m4a")
            )
        }
    }

    @Test
    func failedExportPreservesPreviousMixAndSource() async throws {
        let root = Self.testOutputFolder()
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("mic.m4a")
        let output = root.appendingPathComponent("mixed.m4a")
        let original = Data("previous completed mix".utf8)
        let damaged = Data("damaged source".utf8)
        try damaged.write(to: source)
        try original.write(to: output)
        await #expect(throws: RecordingControllerError.mixedAudioNoSourceTracks) {
            try await MixedAudioPreviewGenerator().createPreview(
                micURL: source, systemURL: root.appendingPathComponent("missing.m4a"), outputURL: output
            )
        }
        #expect(try Data(contentsOf: output) == original)
        #expect(try Data(contentsOf: source) == damaged)
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
            .appendingPathComponent("mixed-preview-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
