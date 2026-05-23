import Foundation
import SQLite3

public final class RecordingMetadataStore {
    public let rootURL: URL

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(rootURL: URL) {
        self.rootURL = rootURL
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.decoder = JSONDecoder()
    }

    public func createNeedsTaggingDraft(
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval
    ) throws -> PostCallDraft {
        let id = Self.makeRecordingID(startedAt: startedAt)
        let sessionFolderURL = sessionFolder(startedAt: startedAt, id: id)
        let metadataURL = sessionFolderURL.appendingPathComponent("metadata.json")

        try FileManager.default.createDirectory(
            at: sessionFolderURL.appendingPathComponent("source", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: sessionFolderURL.appendingPathComponent("export", isDirectory: true),
            withIntermediateDirectories: true
        )

        let metadata = RecordingMetadata(
            id: id,
            title: "Untitled recording",
            startedAt: Self.formatISO8601(startedAt),
            endedAt: Self.formatISO8601(endedAt),
            durationSec: max(0, duration),
            status: .needsTagging
        )

        try write(metadata, metadataURL: metadataURL, sessionFolderURL: sessionFolderURL)

        return PostCallDraft(
            id: id,
            title: metadata.title,
            category: metadata.category,
            participant: metadata.participants.first ?? "",
            tags: metadata.tags,
            status: metadata.status,
            sessionFolderURL: sessionFolderURL,
            metadataURL: metadataURL
        )
    }

    public func saveDraft(_ draft: PostCallDraft) throws {
        var metadata = try readMetadata(at: draft.metadataURL)
        metadata.title = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if metadata.title.isEmpty {
            metadata.title = "Untitled recording"
        }
        metadata.category = draft.category.trimmingCharacters(in: .whitespacesAndNewlines)
        if metadata.category.isEmpty {
            metadata.category = "unsorted"
        }
        metadata.participants = draft.participant.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? []
            : [draft.participant.trimmingCharacters(in: .whitespacesAndNewlines)]
        metadata.tags = Self.normalizedTags(draft.tags)
        metadata.status = draft.status

        try write(metadata, metadataURL: draft.metadataURL, sessionFolderURL: draft.sessionFolderURL)
    }

    public func readMetadata(at url: URL) throws -> RecordingMetadata {
        let data = try Data(contentsOf: url)
        return try decoder.decode(RecordingMetadata.self, from: data)
    }

    public func recordings(filterTag: String?) throws -> [RecordingSummary] {
        try SQLiteRecordingIndex(rootURL: rootURL).recordings(filterTag: filterTag)
    }

    private func write(
        _ metadata: RecordingMetadata,
        metadataURL: URL,
        sessionFolderURL: URL
    ) throws {
        let data = try encoder.encode(metadata)
        try data.write(to: metadataURL, options: [.atomic])
        try SQLiteRecordingIndex(rootURL: rootURL).upsert(
            metadata: metadata,
            metadataURL: metadataURL,
            sessionFolderURL: sessionFolderURL
        )
    }

    private func sessionFolder(startedAt: Date, id: String) -> URL {
        let calendar = Calendar(identifier: .gregorian)
        let year = String(calendar.component(.year, from: startedAt))
        let month = String(format: "%02d", calendar.component(.month, from: startedAt))
        let folderName = "\(Self.formatFolderDate(startedAt))_manual_audio-\(id.suffix(6))"

        return rootURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
            .appendingPathComponent(folderName, isDirectory: true)
    }

    private static func makeRecordingID(startedAt: Date) -> String {
        "rec_\(formatIDDate(startedAt))_\(UUID().uuidString.prefix(8).lowercased())"
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private static func formatIDDate(_ date: Date) -> String {
        let formatter = posixFormatter(format: "yyyy-MM-dd_HH-mm-ss")
        return formatter.string(from: date)
    }

    private static func formatFolderDate(_ date: Date) -> String {
        let formatter = posixFormatter(format: "yyyy-MM-dd_HH-mm")
        return formatter.string(from: date)
    }

    private static func posixFormatter(format: String) -> DateFormatter {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = format
        return dateFormatter
    }
}

private final class SQLiteRecordingIndex {
    private let rootURL: URL
    private var db: OpaquePointer?

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    deinit {
        sqlite3_close(db)
    }

    func upsert(
        metadata: RecordingMetadata,
        metadataURL: URL,
        sessionFolderURL: URL
    ) throws {
        try open()
        try migrate()
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try executePrepared(
                """
                INSERT OR REPLACE INTO recordings (
                    id, title, category, participant, status, started_at, ended_at,
                    duration_sec, metadata_path, folder_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(metadata.id),
                    .text(metadata.title),
                    .text(metadata.category),
                    .text(metadata.participants.first ?? ""),
                    .text(metadata.status.rawValue),
                    .text(metadata.startedAt),
                    .text(metadata.endedAt),
                    .double(metadata.durationSec),
                    .text(metadataURL.path(percentEncoded: false)),
                    .text(sessionFolderURL.path(percentEncoded: false))
                ]
            )

            try executePrepared(
                "DELETE FROM recording_tags WHERE recording_id = ?",
                bindings: [.text(metadata.id)]
            )

            for tag in metadata.tags {
                try executePrepared(
                    "INSERT OR REPLACE INTO recording_tags (recording_id, tag) VALUES (?, ?)",
                    bindings: [.text(metadata.id), .text(tag)]
                )
            }

            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func recordings(filterTag: String?) throws -> [RecordingSummary] {
        try open()
        try migrate()

        let query: String
        let bindings: [SQLiteBinding]

        if let filterTag, !filterTag.isEmpty {
            query = """
            SELECT id, title, category, participant, status, started_at, ended_at,
                   duration_sec, metadata_path, folder_path
            FROM recordings
            WHERE EXISTS (
                SELECT 1 FROM recording_tags
                WHERE recording_tags.recording_id = recordings.id
                  AND recording_tags.tag = ?
            )
            ORDER BY ended_at DESC
            """
            bindings = [.text(filterTag)]
        } else {
            query = """
            SELECT id, title, category, participant, status, started_at, ended_at,
                   duration_sec, metadata_path, folder_path
            FROM recordings
            ORDER BY ended_at DESC
            """
            bindings = []
        }

        let rows = try queryRows(query, bindings: bindings)
        return try rows.map { row in
            let id = row[0]
            return RecordingSummary(
                id: id,
                title: row[1],
                category: row[2],
                participant: row[3],
                tags: try tags(for: id),
                status: TaggingStatus(rawValue: row[4]) ?? .failed,
                startedAt: row[5],
                endedAt: row[6],
                durationSec: Double(row[7]) ?? 0,
                metadataURL: URL(fileURLWithPath: row[8]),
                sessionFolderURL: URL(fileURLWithPath: row[9])
            )
        }
    }

    private func tags(for recordingID: String) throws -> [String] {
        let rows = try queryRows(
            "SELECT tag FROM recording_tags WHERE recording_id = ? ORDER BY tag ASC",
            bindings: [.text(recordingID)]
        )
        return rows.compactMap(\.first)
    }

    private func open() throws {
        guard db == nil else {
            return
        }

        let dbURL = rootURL
            .appendingPathComponent("db", isDirectory: true)
            .appendingPathComponent("app.sqlite")

        try FileManager.default.createDirectory(
            at: dbURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        guard sqlite3_open(dbURL.path(percentEncoded: false), &db) == SQLITE_OK else {
            throw SQLiteIndexError(message: lastError)
        }
    }

    private func migrate() throws {
        try execute(
            """
            CREATE TABLE IF NOT EXISTS recordings (
                id TEXT PRIMARY KEY,
                title TEXT NOT NULL,
                category TEXT NOT NULL,
                participant TEXT NOT NULL,
                status TEXT NOT NULL,
                started_at TEXT NOT NULL,
                ended_at TEXT NOT NULL,
                duration_sec REAL NOT NULL,
                metadata_path TEXT NOT NULL,
                folder_path TEXT NOT NULL
            );
            """
        )
        try execute(
            """
            CREATE TABLE IF NOT EXISTS recording_tags (
                recording_id TEXT NOT NULL,
                tag TEXT NOT NULL,
                PRIMARY KEY (recording_id, tag)
            );
            """
        )
        try execute(
            "CREATE INDEX IF NOT EXISTS idx_recording_tags_tag ON recording_tags(tag);"
        )
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteIndexError(message: lastError)
        }
    }

    private func executePrepared(_ sql: String, bindings: [SQLiteBinding]) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteIndexError(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteIndexError(message: lastError)
        }
    }

    private func queryRows(_ sql: String, bindings: [SQLiteBinding]) throws -> [[String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteIndexError(message: lastError)
        }
        defer { sqlite3_finalize(statement) }

        try bind(bindings, to: statement)

        var rows: [[String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let columnCount = sqlite3_column_count(statement)
            var row: [String] = []
            for index in 0..<columnCount {
                if let text = sqlite3_column_text(statement, index) {
                    row.append(String(cString: text))
                } else {
                    row.append("")
                }
            }
            rows.append(row)
        }

        return rows
    }

    private func bind(_ bindings: [SQLiteBinding], to statement: OpaquePointer?) throws {
        for (offset, binding) in bindings.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32

            switch binding {
            case .text(let value):
                result = sqlite3_bind_text(statement, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case .double(let value):
                result = sqlite3_bind_double(statement, index, value)
            }

            guard result == SQLITE_OK else {
                throw SQLiteIndexError(message: lastError)
            }
        }
    }

    private var lastError: String {
        guard let db, let message = sqlite3_errmsg(db) else {
            return "Unknown SQLite error"
        }

        return String(cString: message)
    }
}

private enum SQLiteBinding {
    case text(String)
    case double(Double)
}

private struct SQLiteIndexError: Error, CustomStringConvertible {
    let message: String

    var description: String {
        message
    }
}
