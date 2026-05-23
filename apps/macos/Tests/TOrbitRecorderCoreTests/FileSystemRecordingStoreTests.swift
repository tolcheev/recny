import Foundation
import Testing
@testable import TOrbitRecorderCore

struct FileSystemRecordingStoreTests {
    @Test
    func startSessionCreatesInboxSessionFolders() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "Zoom/Call", bundleID: "us.zoom.xos")
        )

        #expect(session.folderURL.path(percentEncoded: false).contains("Inbox/Unsorted"))
        #expect(FileManager.default.fileExists(atPath: session.sourceURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: session.exportURL.path(percentEncoded: false)))
    }

    @Test
    func stopSessionWritesMetadataAndMovesToLibrary() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(120)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "Zoom/Call", bundleID: "us.zoom.xos")
        )
        let inboxPath = session.folderURL.path(percentEncoded: false)

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 120,
            status: .needsTagging
        )

        #expect(!FileManager.default.fileExists(atPath: inboxPath))
        #expect(draft.sessionFolderURL.path(percentEncoded: false).contains("Library/2024/05"))
        #expect(FileManager.default.fileExists(atPath: draft.metadataURL.path(percentEncoded: false)))

        let metadata = try store.readMetadata(at: draft.metadataURL)
        #expect(metadata.id == session.id)
        #expect(metadata.schemaVersion == 1)
        #expect(metadata.source.appName == "Zoom/Call")
        #expect(metadata.source.bundleID == "us.zoom.xos")
        #expect(metadata.status == .needsTagging)
        #expect(metadata.ai == "not_started")
        #expect(metadata.sync == "local_only")

        let json = try String(contentsOf: draft.metadataURL, encoding: .utf8)
        #expect(json.contains("\"schema_version\""))
        #expect(json.contains("\"app_name\""))
        #expect(json.contains("\"audio_tracks\""))
        #expect(json.contains("\"ai\""))
        #expect(json.contains("\"sync\""))
    }

    private static func testOutputFolder() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("storage-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
