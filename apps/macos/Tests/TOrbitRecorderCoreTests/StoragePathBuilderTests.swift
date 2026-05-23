import Foundation
import Testing
@testable import TOrbitRecorderCore

struct StoragePathBuilderTests {
    @Test
    func buildsDefaultRootAndBaseDirectories() {
        let root = URL(fileURLWithPath: "/tmp/TOrbitRecorderTests", isDirectory: true)
        let builder = StoragePathBuilder(rootURL: root)

        #expect(Self.trimmedPath(builder.inboxUnsortedURL).hasSuffix("Inbox/Unsorted"))
        #expect(Self.trimmedPath(builder.inboxShortURL).hasSuffix("Inbox/Short"))
        #expect(Self.trimmedPath(builder.inboxFailedURL).hasSuffix("Inbox/Failed"))
        #expect(builder.dbURL.path(percentEncoded: false).hasSuffix("db/app.sqlite"))
        #expect(Self.trimmedPath(builder.logsURL).hasSuffix("logs"))
    }

    @Test
    func buildsFilesystemSafeLibraryFolderName() {
        let root = URL(fileURLWithPath: "/tmp/TOrbitRecorderTests", isDirectory: true)
        let builder = StoragePathBuilder(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let folderName = builder.libraryFolderName(
            startedAt: startedAt,
            sourceAppName: "Zoom/Call: Vlad?",
            suffix: nil
        )

        #expect(folderName == "2024-05-23_12-40_zoom-call-vlad_audio")
        #expect(!folderName.contains("/"))
        #expect(!folderName.contains(":"))
        #expect(!folderName.contains("?"))
    }

    private static func trimmedPath(_ url: URL) -> String {
        url.path(percentEncoded: false).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}
