import Foundation
import Testing
@testable import TOrbitRecorderCore

struct FileLogStoreTests {
    @Test
    func writesAndReadsRecentLogLines() throws {
        let logsURL = try Self.makeTemporaryLogsURL()
        let store = FileLogStore(logsDirectoryURL: logsURL, maxFileSizeBytes: 5 * 1024 * 1024)

        try store.clear()
        try store.write(level: .info, category: "app", message: "app start")
        try store.write(level: .error, category: "recording", message: "recording failure")

        let lines = try store.recentLines(limit: 100)

        #expect(lines.count == 2)
        #expect(lines[0].contains("[INFO]"))
        #expect(lines[0].contains("[app]"))
        #expect(lines[0].contains("app start"))
        #expect(lines[1].contains("[ERROR]"))
        #expect(lines[1].contains("[recording]"))
        #expect(lines[1].contains("recording failure"))
        #expect(FileManager.default.fileExists(atPath: store.logFileURL.path(percentEncoded: false)))
    }

    @Test
    func rotatesActiveLogWhenMaxSizeIsExceeded() throws {
        let logsURL = try Self.makeTemporaryLogsURL()
        let store = FileLogStore(logsDirectoryURL: logsURL, maxFileSizeBytes: 180)

        try store.clear()
        try store.write(level: .info, category: "app", message: String(repeating: "a", count: 80))
        try store.write(level: .info, category: "app", message: String(repeating: "b", count: 80))

        let active = try String(contentsOf: store.logFileURL, encoding: .utf8)
        let archive = try String(contentsOf: store.archiveLogFileURL, encoding: .utf8)

        #expect(archive.contains(String(repeating: "a", count: 80)))
        #expect(active.contains(String(repeating: "b", count: 80)))
        #expect(!active.contains(String(repeating: "a", count: 80)))
    }

    private static func makeTemporaryLogsURL() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("TOrbitRecorderFileLogStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
}
