import Foundation
import SQLite3

public final class FileSystemRecordingStore {
    public let rootURL: URL
    public let paths: StoragePathBuilder

    private let codec: RecordingMetadataCodec

    public init(rootURL: URL = RecordingPaths.defaultRoot) {
        self.rootURL = rootURL
        self.paths = StoragePathBuilder(rootURL: rootURL)
        self.codec = RecordingMetadataCodec()
    }

    public func prepareRoot() throws {
        for directory in paths.baseDirectories() {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }

    public func startSession(
        startedAt: Date,
        source: RecordingSource = RecordingSource()
    ) throws -> RecordingSession {
        try prepareRoot()

        let id = makeRecordingID(startedAt: startedAt)
        let folderURL = paths.temporarySessionURL(id: id)
        let session = RecordingSession(
            id: id,
            startedAt: startedAt,
            source: source,
            folderURL: folderURL
        )

        try FileManager.default.createDirectory(
            at: session.sourceURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: session.exportURL,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: session.segmentsURL,
            withIntermediateDirectories: true
        )
        try writeRecoveryMetadata(makeInitialRecoveryMetadata(for: session), to: session.recoveryMetadataURL)

        AppLogger.storage.info("Created temporary recording session folder: \(folderURL.path(percentEncoded: false), privacy: .public)")

        return session
    }

    public func stopSession(
        _ session: RecordingSession,
        endedAt: Date,
        duration: TimeInterval,
        status: TaggingStatus,
        audioTracks: [AudioTrackMetadata]? = nil,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds
    ) throws -> PostCallDraft {
        try prepareRoot()

        let finalStatus = TaggingStatus.finalizedStatus(
            forDuration: duration,
            preferredStatus: status,
            thresholdSeconds: shortRecordingThresholdSeconds
        )
        let finalFolderURL = try uniqueFinalSessionURL(for: session, status: finalStatus)
        try FileManager.default.createDirectory(
            at: finalFolderURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: session.folderURL, to: finalFolderURL)

        let finalMetadataURL = finalFolderURL.appendingPathComponent("metadata.json")
        let metadata = makeMetadata(
            session: session,
            endedAt: endedAt,
            duration: duration,
            status: finalStatus,
            audioTracks: audioTracks
        )

        try write(metadata, metadataURL: finalMetadataURL, sessionFolderURL: finalFolderURL)
        AppLogger.storage.info("Finalized recording metadata: \(finalMetadataURL.path(percentEncoded: false), privacy: .public)")

        return PostCallDraft(
            id: metadata.id,
            title: metadata.title,
            category: metadata.category,
            participant: metadata.participants.first ?? "",
            tags: metadata.tags,
            status: metadata.status,
            sessionFolderURL: finalFolderURL,
            metadataURL: finalMetadataURL
        )
    }

    public func createNeedsTaggingDraft(
        startedAt: Date,
        endedAt: Date,
        duration: TimeInterval
    ) throws -> PostCallDraft {
        let session = try startSession(
            startedAt: startedAt,
            source: RecordingSource()
        )
        return try stopSession(
            session,
            endedAt: endedAt,
            duration: duration,
            status: .needsTagging
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

        let participant = draft.participant.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.participants = participant.isEmpty ? [] : [participant]
        metadata.tags = normalizedTags(draft.tags)
        metadata.status = draft.status

        try write(metadata, metadataURL: draft.metadataURL, sessionFolderURL: draft.sessionFolderURL)
    }

    public func readMetadata(at url: URL) throws -> RecordingMetadata {
        try codec.read(from: url)
    }

    public func readRecoveryMetadata(at url: URL) throws -> RecoveryMetadata {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        return try decoder.decode(RecoveryMetadata.self, from: data)
    }

    public func writeRecoveryMetadata(_ metadata: RecoveryMetadata, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(metadata)
        try data.write(to: url, options: [.atomic])
    }

    public func recoverableSessions() throws -> [RecoverableRecordingSummary] {
        try prepareRoot()

        let folderURLs = try FileManager.default.contentsOfDirectory(
            at: paths.inboxUnsortedURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var summaries: [RecoverableRecordingSummary] = []
        for folderURL in folderURLs {
            let values = try folderURL.resourceValues(forKeys: [.isDirectoryKey])
            guard values.isDirectory == true else {
                continue
            }

            let recoveryURL = folderURL.appendingPathComponent("recovery.json")
            guard FileManager.default.fileExists(atPath: recoveryURL.path(percentEncoded: false)) else {
                continue
            }

            var recovery = try readRecoveryMetadata(at: recoveryURL)
            guard recovery.status == .recording || recovery.status == .recoverable else {
                continue
            }

            recovery.status = .recoverable
            recovery.updatedAt = formatISO8601(Date())
            try writeRecoveryMetadata(recovery, to: recoveryURL)

            let segmentCount = try usableSegmentURLs(in: folderURL).count
            summaries.append(
                RecoverableRecordingSummary(
                    id: recovery.recordingID,
                    status: recovery.status,
                    startedAt: recovery.startedAt,
                    updatedAt: recovery.updatedAt,
                    folderURL: folderURL,
                    recoveryMetadataURL: recoveryURL,
                    segmentCount: segmentCount
                )
            )
        }

        return summaries.sorted { $0.startedAt > $1.startedAt }
    }

    public func recordings(filterTag: String?) throws -> [RecordingSummary] {
        try recordings(
            filters: RecordingListFilters(tags: filterTag.map { [$0] } ?? [])
        )
    }

    public func recordings(filters: RecordingListFilters) throws -> [RecordingSummary] {
        try prepareRoot()
        let index = SQLiteRecordingIndex(rootURL: rootURL, dbURL: paths.dbURL)

        if try index.isEmpty() {
            try reindexMetadataFiles(with: index)
        }

        return try index.recordings(filters: filters)
    }

    public func updateRecording(id: String, title: String, tags: [String]) throws {
        let index = SQLiteRecordingIndex(rootURL: rootURL, dbURL: paths.dbURL)
        if try index.isEmpty() {
            try reindexMetadataFiles(with: index)
        }

        guard let summary = try index.recording(id: id) else {
            throw SQLiteIndexError(message: "Recording not found: \(id)")
        }

        var metadata = try readMetadata(at: summary.metadataURL)
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        metadata.title = trimmedTitle.isEmpty ? "Untitled recording" : trimmedTitle
        metadata.tags = normalizedTags(tags)

        try write(metadata, metadataURL: summary.metadataURL, sessionFolderURL: summary.sessionFolderURL)
    }

    public func deleteLocalRecord(_ summary: RecordingSummary) throws {
        let index = SQLiteRecordingIndex(rootURL: rootURL, dbURL: paths.dbURL)
        try FileManager.default.removeItemIfExists(at: summary.sessionFolderURL)
        try index.delete(recordingID: summary.id)
    }

    private func write(
        _ metadata: RecordingMetadata,
        metadataURL: URL,
        sessionFolderURL: URL
    ) throws {
        try codec.write(metadata, to: metadataURL)
        try SQLiteRecordingIndex(rootURL: rootURL, dbURL: paths.dbURL).upsert(
            metadata: metadata,
            metadataURL: metadataURL,
            sessionFolderURL: sessionFolderURL
        )
    }

    private func reindexMetadataFiles(with index: SQLiteRecordingIndex) throws {
        for metadataURL in try metadataURLsForReindex() {
            do {
                let metadata = try readMetadata(at: metadataURL)
                try index.upsert(
                    metadata: metadata,
                    metadataURL: metadataURL,
                    sessionFolderURL: metadataURL.deletingLastPathComponent()
                )
            } catch {
                AppLogger.storage.error("Failed to index metadata file \(metadataURL.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func metadataURLsForReindex() throws -> [URL] {
        let roots = [paths.libraryURL, paths.inboxURL].filter {
            FileManager.default.fileExists(atPath: $0.path(percentEncoded: false))
        }
        var urls: [URL] = []

        for root in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.lastPathComponent == "metadata.json" {
                urls.append(url)
            }
        }

        return urls
    }

    private func makeMetadata(
        session: RecordingSession,
        endedAt: Date,
        duration: TimeInterval,
        status: TaggingStatus,
        audioTracks: [AudioTrackMetadata]?
    ) -> RecordingMetadata {
        RecordingMetadata(
            id: session.id,
            title: "Untitled recording",
            startedAt: formatISO8601(session.startedAt),
            endedAt: formatISO8601(endedAt),
            durationSec: max(0, duration),
            source: session.source,
            audioTracks: audioTracks ?? [
                AudioTrackMetadata(
                    kind: "microphone",
                    relativePath: "source/mic.m4a",
                    status: "not_written",
                    error: "stub controller does not write audio"
                ),
                AudioTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    status: "not_written",
                    error: "stub controller does not write audio"
                ),
                AudioTrackMetadata(
                    kind: "mixed",
                    relativePath: "export/mixed.m4a",
                    status: "not_written",
                    error: "stub controller does not write audio"
                )
            ],
            status: status
        )
    }

    private func makeInitialRecoveryMetadata(for session: RecordingSession) -> RecoveryMetadata {
        let now = formatISO8601(session.startedAt)
        return RecoveryMetadata(
            recordingID: session.id,
            status: .recording,
            startedAt: now,
            updatedAt: now,
            source: session.source,
            segments: [
                RecoverySegmentMetadata(
                    kind: "microphone",
                    relativePath: "source/segments/mic-0001.m4a",
                    status: "planned"
                ),
                RecoverySegmentMetadata(
                    kind: "system",
                    relativePath: "source/segments/system-0001.m4a",
                    status: "planned"
                )
            ]
        )
    }

    private func usableSegmentURLs(in folderURL: URL) throws -> [URL] {
        let segmentsURL = folderURL
            .appendingPathComponent("source", isDirectory: true)
            .appendingPathComponent("segments", isDirectory: true)

        guard FileManager.default.fileExists(atPath: segmentsURL.path(percentEncoded: false)) else {
            return []
        }

        return try FileManager.default.contentsOfDirectory(
            at: segmentsURL,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )
        .filter { url in
            ((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) > 0
        }
    }

    private func uniqueFinalSessionURL(
        for session: RecordingSession,
        status: TaggingStatus
    ) throws -> URL {
        switch status {
        case .shortRecording:
            return try uniqueInboxSessionURL(for: session, inboxURL: paths.inboxShortURL)
        case .failed:
            return try uniqueInboxSessionURL(for: session, inboxURL: paths.inboxFailedURL)
        default:
            return try uniqueLibrarySessionURL(for: session)
        }
    }

    private func uniqueInboxSessionURL(for session: RecordingSession, inboxURL: URL) throws -> URL {
        var suffix: String?
        var candidate = inboxURL.appendingPathComponent(
            paths.libraryFolderName(
                startedAt: session.startedAt,
                sourceAppName: session.source.appName,
                suffix: suffix
            ),
            isDirectory: true
        )

        if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        suffix = String(session.id.suffix(8))
        candidate = inboxURL.appendingPathComponent(
            paths.libraryFolderName(
                startedAt: session.startedAt,
                sourceAppName: session.source.appName,
                suffix: suffix
            ),
            isDirectory: true
        )

        if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        var index = 2
        while true {
            candidate = inboxURL.appendingPathComponent(
                paths.libraryFolderName(
                    startedAt: session.startedAt,
                    sourceAppName: session.source.appName,
                    suffix: "\(suffix ?? session.id)-\(index)"
                ),
                isDirectory: true
            )

            if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }

            index += 1
        }
    }

    private func uniqueLibrarySessionURL(for session: RecordingSession) throws -> URL {
        var suffix: String?
        var candidate = paths.librarySessionURL(
            startedAt: session.startedAt,
            sourceAppName: session.source.appName,
            suffix: suffix
        )

        if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        suffix = String(session.id.suffix(8))
        candidate = paths.librarySessionURL(
            startedAt: session.startedAt,
            sourceAppName: session.source.appName,
            suffix: suffix
        )

        if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
            return candidate
        }

        var index = 2
        while true {
            candidate = paths.librarySessionURL(
                startedAt: session.startedAt,
                sourceAppName: session.source.appName,
                suffix: "\(suffix ?? session.id)-\(index)"
            )

            if !FileManager.default.fileExists(atPath: candidate.path(percentEncoded: false)) {
                return candidate
            }

            index += 1
        }
    }

    private func makeRecordingID(startedAt: Date) -> String {
        "rec_\(paths.formatDate(startedAt, format: "yyyy-MM-dd_HH-mm-ss"))_\(UUID().uuidString.prefix(8).lowercased())"
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { tag in
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else {
                return nil
            }
            return trimmed
        }
    }

    private func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

private final class SQLiteRecordingIndex {
    private let rootURL: URL
    private let dbURL: URL
    private var db: OpaquePointer?

    init(rootURL: URL, dbURL: URL) {
        self.rootURL = rootURL
        self.dbURL = dbURL
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
                    id, title, category, participant, status, source_app,
                    started_at, ended_at, duration_sec, metadata_path, folder_path
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                """,
                bindings: [
                    .text(metadata.id),
                    .text(metadata.title),
                    .text(metadata.category),
                    .text(metadata.participants.first ?? ""),
                    .text(metadata.status.rawValue),
                    .text(metadata.source.appName),
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
                    "INSERT OR REPLACE INTO tags (tag) VALUES (?)",
                    bindings: [.text(tag)]
                )
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
        try recordings(
            filters: RecordingListFilters(tags: filterTag.map { [$0] } ?? [])
        )
    }

    func recordings(filters: RecordingListFilters) throws -> [RecordingSummary] {
        try open()
        try migrate()

        var whereClauses: [String] = []
        var bindings: [SQLiteBinding] = []

        let dateText = filters.dateText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !dateText.isEmpty {
            whereClauses.append("(started_at LIKE ? OR ended_at LIKE ?)")
            bindings.append(.text("%\(dateText)%"))
            bindings.append(.text("%\(dateText)%"))
        }

        if let status = filters.status {
            whereClauses.append("status = ?")
            bindings.append(.text(status.rawValue))
        }

        let sourceAppText = filters.sourceAppText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !sourceAppText.isEmpty {
            whereClauses.append("LOWER(source_app) LIKE LOWER(?)")
            bindings.append(.text("%\(sourceAppText)%"))
        }

        let titleText = filters.titleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !titleText.isEmpty {
            whereClauses.append("LOWER(title) LIKE LOWER(?)")
            bindings.append(.text("%\(titleText)%"))
        }

        for tag in filters.tags where !tag.isEmpty {
            whereClauses.append(
                """
                EXISTS (
                    SELECT 1 FROM recording_tags
                    WHERE recording_tags.recording_id = recordings.id
                      AND recording_tags.tag = ?
                )
                """
            )
            bindings.append(.text(tag))
        }

        let whereSQL = whereClauses.isEmpty ? "" : "WHERE \(whereClauses.joined(separator: " AND "))"
        let query = """
        SELECT id, title, category, participant, status, source_app, started_at, ended_at,
               duration_sec, metadata_path, folder_path
        FROM recordings
        \(whereSQL)
        ORDER BY ended_at DESC
        """

        let rows = try queryRows(query, bindings: bindings)
        return try rows.map(summary(from:))
    }

    func recording(id: String) throws -> RecordingSummary? {
        try open()
        try migrate()

        let rows = try queryRows(
            """
            SELECT id, title, category, participant, status, source_app, started_at, ended_at,
                   duration_sec, metadata_path, folder_path
            FROM recordings
            WHERE id = ?
            LIMIT 1
            """,
            bindings: [.text(id)]
        )

        guard let row = rows.first else {
            return nil
        }

        return try summary(from: row)
    }

    func delete(recordingID: String) throws {
        try open()
        try migrate()
        try execute("BEGIN IMMEDIATE TRANSACTION")

        do {
            try executePrepared("DELETE FROM recording_tags WHERE recording_id = ?", bindings: [.text(recordingID)])
            try executePrepared("DELETE FROM recordings WHERE id = ?", bindings: [.text(recordingID)])
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    func isEmpty() throws -> Bool {
        try open()
        try migrate()
        return try queryRows("SELECT id FROM recordings LIMIT 1", bindings: []).isEmpty
    }

    private func summary(from row: [String]) throws -> RecordingSummary {
        let id = row[0]
        return RecordingSummary(
            id: id,
            title: row[1],
            category: row[2],
            participant: row[3],
            tags: try tags(for: id),
            status: TaggingStatus(rawValue: row[4]) ?? .failed,
            sourceApp: row[5],
            startedAt: row[6],
            endedAt: row[7],
            durationSec: Double(row[8]) ?? 0,
            metadataURL: URL(fileURLWithPath: row[9]),
            sessionFolderURL: URL(fileURLWithPath: row[10])
        )
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
                source_app TEXT NOT NULL DEFAULT '',
                started_at TEXT NOT NULL,
                ended_at TEXT NOT NULL,
                duration_sec REAL NOT NULL,
                metadata_path TEXT NOT NULL,
                folder_path TEXT NOT NULL
            );
            """
        )
        try addColumnIfNeeded(table: "recordings", column: "source_app", definition: "TEXT NOT NULL DEFAULT ''")
        try execute(
            """
            CREATE TABLE IF NOT EXISTS tags (
                tag TEXT PRIMARY KEY
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
        try execute("CREATE INDEX IF NOT EXISTS idx_recordings_started_at ON recordings(started_at);")
        try execute("CREATE INDEX IF NOT EXISTS idx_recordings_status ON recordings(status);")
        try execute("CREATE INDEX IF NOT EXISTS idx_recordings_source_app ON recordings(source_app);")
        try execute("CREATE INDEX IF NOT EXISTS idx_recording_tags_tag ON recording_tags(tag);")
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        guard try !tableColumns(table).contains(column) else {
            return
        }

        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition);")
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let rows = try queryRows("PRAGMA table_info(\(table));", bindings: [])
        return Set(rows.compactMap { row in
            guard row.count > 1 else {
                return nil
            }
            return row[1]
        })
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

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        guard fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        try removeItem(at: url)
    }
}
