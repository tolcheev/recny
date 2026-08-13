import Foundation
import Testing
@testable import RecnyCore

struct RecordingRecoveryControllerTests {
    @Test
    func recoversFinalFilesFromUsableSegment() async throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let fixtureSourceURL = root
            .appendingPathComponent("fixture", isDirectory: true)
            .appendingPathComponent("source", isDirectory: true)
        let fixtureExportURL = root
            .appendingPathComponent("fixture", isDirectory: true)
            .appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: fixtureSourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fixtureExportURL, withIntermediateDirectories: true)
        let fixtureInputURL = fixtureSourceURL.appendingPathComponent("input.aiff")
        let fixtureM4AURL = fixtureExportURL.appendingPathComponent("mixed.m4a")
        try FileManager.default.copyItem(at: Self.fixtureAudioURL(), to: fixtureInputURL)

        _ = try await MixedAudioPreviewGenerator().createPreview(
            micURL: fixtureInputURL,
            systemURL: fixtureSourceURL.appendingPathComponent("missing.m4a"),
            outputURL: fixtureM4AURL
        )
        try FileManager.default.copyItem(
            at: fixtureM4AURL,
            to: session.segmentsURL.appendingPathComponent("mic-0001.m4a")
        )

        let summary = try #require(store.recoverableSessions().first)
        let draft = try await RecordingRecoveryController(store: store).recover(summary)

        #expect(draft.status == .needsReview)
        #expect(draft.sessionFolderURL.path(percentEncoded: false).contains("Library/2024/05"))
        #expect(FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("source/mic.m4a").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("export/mixed.m4a").path(percentEncoded: false)))

        let metadata = try store.readMetadata(at: draft.metadataURL)
        #expect(metadata.status == .needsReview)
        #expect(metadata.audioTracks.contains { $0.kind == "mixed" && $0.status == "completed" })
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
            .appendingPathComponent("recovery-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
