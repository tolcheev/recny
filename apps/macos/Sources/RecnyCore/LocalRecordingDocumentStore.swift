import Foundation

public struct LocalRecordingDocumentStore: Sendable {
    public let sessionFolderURL: URL
    public var directory: URL { sessionFolderURL.appendingPathComponent("transcript", isDirectory: true) }
    private var fileManager: FileManager { .default }
    public init(sessionFolderURL: URL) { self.sessionFolderURL = sessionFolderURL }

    public func checkedURL(_ name: String) throws -> URL {
        let root = sessionFolderURL.resolvingSymlinksInPath().standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else { throw LocalDocumentError.unsafePath }
        let url = directory.appendingPathComponent(name)
        guard url.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(root.path + "/"),
              directory.resolvingSymlinksInPath().standardizedFileURL.path == root.appendingPathComponent("transcript", isDirectory: true).standardizedFileURL.path else {
            throw LocalDocumentError.unsafePath
        }
        return url
    }
    public func prepare() throws {
        _ = try checkedURL("segments.json")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    public func loadTranscript() throws -> LocalRecordingTranscript? {
        if let data = try read("segments.json") {
            let result = try JSONDecoder().decode(LocalRecordingTranscript.self, from: data)
            try result.validate()
            return result
        }
        if let data = try read("transcript.srt"), let text = String(data: data, encoding: .utf8) {
            return try LocalRecordingTranscript(source: nil, segments: LocalTranscriptParser.srt(text))
        }
        if let data = try read("transcript.txt"), let text = String(data: data, encoding: .utf8) {
            return try LocalRecordingTranscript(source: nil, segments: LocalTranscriptParser.plainText(text))
        }
        return nil
    }
    public func saveTranscript(_ transcript: LocalRecordingTranscript, exports: [String: Data] = [:]) throws {
        try transcript.validate()
        var files = exports.filter { ["transcript.txt", "transcript.srt", "transcript.vtt", "transcript.json"].contains($0.key) }
        files["segments.json"] = try encode(transcript)
        if files["transcript.txt"] == nil { files["transcript.txt"] = Data(transcript.segments.map(\.text).joined(separator: "\n").utf8) }
        try commit(files)
    }
    public func loadNotes() throws -> LocalStructuredNotes? {
        guard let data = try read("notes.json") else { return nil }
        return try JSONDecoder().decode(LocalStructuredNotes.self, from: data)
    }
    public func loadNotesMarkdown() throws -> String? {
        guard let data = try read("notes.md") else { return nil }
        guard let text = String(data: data, encoding: .utf8) else { throw LocalDocumentError.invalidNotes }
        return text
    }
    public func saveNotes(_ notes: LocalStructuredNotes, segments: [LocalTranscriptSegment]) throws {
        try notes.validate(segments: segments)
        var versioned = notes
        versioned.transcriptSHA256 = LocalRecordingTranscript.digest(segments)
        try preserveNotes()
        try commit(["notes.json": encode(versioned), "notes.md": Data(versioned.markdown.utf8)])
    }
    public func saveEditedNotes(_ text: String, expected: String? = nil) throws {
        guard text.utf8.count <= 10_000_000 else { throw LocalDocumentError.invalidNotes }
        if let expected, try loadNotesMarkdown() != expected { throw LocalDocumentError.editConflict }
        try preserveNotes()
        try commit(["notes.md": Data(text.utf8)])
    }
    public func read(_ name: String) throws -> Data? {
        let url = try checkedURL(name)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true, (values.fileSize ?? Int.max) <= 64_000_000 else { throw LocalDocumentError.unsafePath }
        return try Data(contentsOf: url)
    }
    public func write<T: Encodable>(_ value: T, name: String) throws {
        try commit([name: encode(value)])
    }
    private func preserveNotes() throws {
        guard let current = try read("notes.md") else { return }
        let history = try checkedURL("history")
        try fileManager.createDirectory(at: history, withIntermediateDirectories: true)
        try current.write(to: try checkedURL("history/\(UUID().uuidString).md"), options: .atomic)
    }
    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
    private func commit(_ files: [String: Data]) throws {
        try prepare()
        var previous: [String: Data] = [:]
        var absent: Set<String> = []
        for name in files.keys {
            if let data = try read(name) { previous[name] = data } else { absent.insert(name) }
        }
        do {
            for (name, data) in files.sorted(by: { $0.key < $1.key }) {
                try data.write(to: checkedURL(name), options: .atomic)
            }
        } catch {
            for (name, data) in previous { try? data.write(to: checkedURL(name), options: .atomic) }
            for name in absent { if let url = try? checkedURL(name) { try? fileManager.removeItem(at: url) } }
            throw error
        }
    }
}
