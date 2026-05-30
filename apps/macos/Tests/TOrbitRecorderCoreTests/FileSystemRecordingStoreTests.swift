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
        #expect(FileManager.default.fileExists(atPath: session.segmentsURL.path(percentEncoded: false)))
    }

    @Test
    func startSessionWritesRecoveryMetadata() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )

        let recovery = try store.readRecoveryMetadata(at: session.recoveryMetadataURL)
        #expect(recovery.recordingID == session.id)
        #expect(recovery.status == .recording)
        #expect(recovery.source.appName == "Zoom")
        #expect(recovery.segments.map(\.relativePath).contains("source/segments/mic-0001.m4a"))
        #expect(recovery.segments.map(\.relativePath).contains("source/segments/system-0001.m4a"))
    }

    @Test
    func recoverableSessionsMarksInterruptedRecording() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(
                appName: "Zoom",
                bundleID: "us.zoom.xos",
                trigger: "autostart",
                ruleID: "autostart.v2.zoom",
                confidence: "high",
                reason: "Zoom active with microphone activity."
            )
        )
        try Data([1, 2, 3]).write(to: session.segmentsURL.appendingPathComponent("mic-0001.m4a"))

        let recoverable = try store.recoverableSessions()

        let summary = try #require(recoverable.first)
        #expect(summary.id == session.id)
        #expect(summary.status == .recoverable)
        #expect(summary.folderURL == session.folderURL)
        #expect(summary.segmentCount == 1)

        let recovery = try store.readRecoveryMetadata(at: session.recoveryMetadataURL)
        #expect(recovery.status == .recoverable)
    }

    @Test
    func recoverableSessionsSkipsEmptyInterruptedFolders() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        _ = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )

        #expect(try store.recoverableSessions().isEmpty)
    }

    @Test
    func recoverableSessionsIncludesFinalAudioWithoutSegments() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(
                appName: "Zoom",
                bundleID: "us.zoom.xos",
                trigger: "autostart",
                ruleID: "autostart.v2.zoom",
                confidence: "high",
                reason: "Zoom active with microphone activity."
            )
        )
        try Data([1, 2, 3]).write(to: session.sourceURL.appendingPathComponent("mic.m4a"))

        let recoverable = try store.recoverableSessions()

        let summary = try #require(recoverable.first)
        #expect(summary.id == session.id)
        #expect(summary.segmentCount == 0)
        #expect(summary.recoverableFileCount == 1)
    }

    @Test
    func clearEmptyRecoverableSessionsRemovesOnlyEmptyInterruptedFolders() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let empty = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let usable = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_030),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        try Data([1, 2, 3]).write(to: usable.segmentsURL.appendingPathComponent("mic-0001.m4a"))

        let removed = try store.clearEmptyRecoverableSessions()

        #expect(removed == 1)
        #expect(!FileManager.default.fileExists(atPath: empty.folderURL.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: usable.folderURL.path(percentEncoded: false)))
        #expect(try store.recoverableSessions().map(\.id) == [usable.id])
    }

    @Test
    func discardEmptyInterruptedSessionRemovesOnlyWhenNoUsableFilesExist() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let empty = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let usable = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_030),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        try Data([1, 2, 3]).write(to: usable.segmentsURL.appendingPathComponent("mic-0001.m4a"))

        #expect(try store.discardSessionIfEmpty(empty))
        #expect(!FileManager.default.fileExists(atPath: empty.folderURL.path(percentEncoded: false)))
        #expect(!((try store.discardSessionIfEmpty(usable))))
        #expect(FileManager.default.fileExists(atPath: usable.folderURL.path(percentEncoded: false)))
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

    @Test
    func stopSessionRemovesRecoveryArtifactsForCompletedRecording() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(120)
        let session = try store.startSession(startedAt: startedAt)
        try Data([1, 2, 3]).write(to: session.segmentsURL.appendingPathComponent("mic-0001.m4a"))
        try Data([4, 5, 6]).write(to: session.segmentsURL.appendingPathComponent("system-0001.m4a"))

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 120,
            status: .needsTagging
        )

        #expect(FileManager.default.fileExists(atPath: draft.metadataURL.path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("recovery.json").path(percentEncoded: false)))
        #expect(!FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("source/segments").path(percentEncoded: false)))
    }

    @Test
    func stopSessionKeepsRecoveryArtifactsForFailedRecording() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(10)
        let session = try store.startSession(startedAt: startedAt)
        try Data([1, 2, 3]).write(to: session.segmentsURL.appendingPathComponent("mic-0001.m4a"))

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 10,
            status: .failed
        )

        #expect(FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("recovery.json").path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: draft.sessionFolderURL.appendingPathComponent("source/segments/mic-0001.m4a").path(percentEncoded: false)))
    }

    @Test
    func stopSessionCanPersistCompletedMicrophoneTrack() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(10)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "ToRec", bundleID: "com.torbit.recorder")
        )
        let micURL = session.sourceURL.appendingPathComponent("mic.m4a")
        try Data([1, 2, 3, 4]).write(to: micURL)

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 10,
            status: .needsTagging,
            audioTracks: [
                AudioTrackMetadata(
                    kind: "microphone",
                    relativePath: "source/mic.m4a",
                    codec: "aac",
                    container: "m4a",
                    durationSec: 10,
                    sampleRate: 48_000,
                    channels: 1,
                    bitrate: 128_000,
                    fileSizeBytes: 4,
                    status: "completed"
                )
            ]
        )

        let metadata = try store.readMetadata(at: draft.metadataURL)
        let micTrack = try #require(metadata.audioTracks.first)
        #expect(micTrack.kind == "microphone")
        #expect(micTrack.codec == "aac")
        #expect(micTrack.container == "m4a")
        #expect(micTrack.sampleRate == 48_000)
        #expect(micTrack.channels == 1)
        #expect(micTrack.bitrate == 128_000)
        #expect(micTrack.fileSizeBytes == 4)
        #expect(micTrack.status == "completed")
    }

    @Test
    func stopSessionCanPersistCompletedSystemAudioTrack() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(10)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "ToRec", bundleID: "com.torbit.recorder")
        )
        let systemURL = session.sourceURL.appendingPathComponent("system.m4a")
        try Data([1, 2, 3, 4]).write(to: systemURL)

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 10,
            status: .needsTagging,
            audioTracks: [
                AudioTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    codec: "aac",
                    container: "m4a",
                    durationSec: 10,
                    sampleRate: 48_000,
                    channels: 2,
                    bitrate: 128_000,
                    status: "completed"
                )
            ]
        )

        let metadata = try store.readMetadata(at: draft.metadataURL)
        let systemTrack = try #require(metadata.audioTracks.first)
        #expect(systemTrack.kind == "system")
        #expect(systemTrack.codec == "aac")
        #expect(systemTrack.container == "m4a")
        #expect(systemTrack.sampleRate == 48_000)
        #expect(systemTrack.channels == 2)
        #expect(systemTrack.bitrate == 128_000)
        #expect(systemTrack.status == "completed")
    }

    @Test
    func sqliteIndexSupportsInsertReadAndFilters() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(10)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 10,
            status: .needsReview,
            audioTracks: []
        )

        var postCallDraft = draft
        postCallDraft.title = "Lead Review"
        postCallDraft.category = "sales"
        postCallDraft.participant = "Ivan"
        postCallDraft.tags = ["#лид", "#важное"]
        postCallDraft.status = .saved
        try store.saveDraft(postCallDraft)

        let filtered = try store.recordings(
            filters: RecordingListFilters(
                dateText: "2024-05",
                status: .saved,
                sourceAppText: "zoom",
                titleText: "lead",
                tags: ["#лид"]
            )
        )

        let summary = try #require(filtered.first)
        #expect(summary.id == session.id)
        #expect(summary.title == "Lead Review")
        #expect(summary.status == .saved)
        #expect(summary.sourceApp == "Zoom")
        #expect(summary.tags == ["#важное", "#лид"])
    }

    @Test
    func recordingsScansMetadataWhenSQLiteIsEmpty() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let endedAt = startedAt.addingTimeInterval(10)

        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "FaceTime", bundleID: "com.apple.FaceTime")
        )
        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 10,
            status: .needsTagging,
            audioTracks: []
        )

        try FileManager.default.removeItem(at: store.paths.dbURL)

        let recordings = try store.recordings(filters: RecordingListFilters(sourceAppText: "facetime"))

        #expect(recordings.map(\.id).contains(draft.id))
        #expect(FileManager.default.fileExists(atPath: store.paths.dbURL.path(percentEncoded: false)))
    }

    @Test
    func recordingsReindexesMetadataMissingFromNonEmptySQLite() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let firstSession = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let firstDraft = try store.stopSession(
            firstSession,
            endedAt: Date(timeIntervalSince1970: 1_716_468_060),
            duration: 60,
            status: .needsTagging,
            audioTracks: []
        )
        let secondSession = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_120),
            source: RecordingSource(appName: "FaceTime", bundleID: "com.apple.FaceTime")
        )
        let secondDraft = try store.stopSession(
            secondSession,
            endedAt: Date(timeIntervalSince1970: 1_716_468_180),
            duration: 60,
            status: .needsTagging,
            audioTracks: []
        )

        try FileManager.default.removeItem(at: store.paths.dbURL)
        let firstMetadata = try store.readMetadata(at: firstDraft.metadataURL)
        try store.writeMetadata(
            firstMetadata,
            metadataURL: firstDraft.metadataURL,
            sessionFolderURL: firstDraft.sessionFolderURL
        )

        let recordings = try store.recordings(filters: RecordingListFilters())

        #expect(Set(recordings.map(\.id)) == Set([firstDraft.id, secondDraft.id]))
    }

    @Test
    func recordingsPrunesDeletedSessionFoldersFromIndex() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let keptSession = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let keptDraft = try store.stopSession(
            keptSession,
            endedAt: Date(timeIntervalSince1970: 1_716_468_060),
            duration: 60,
            status: .needsTagging,
            audioTracks: []
        )
        let deletedSession = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_120),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let deletedDraft = try store.stopSession(
            deletedSession,
            endedAt: Date(timeIntervalSince1970: 1_716_468_180),
            duration: 60,
            status: .needsTagging,
            audioTracks: []
        )

        try FileManager.default.removeItem(at: deletedDraft.sessionFolderURL)

        let recordings = try store.recordings(filters: RecordingListFilters())

        #expect(recordings.map(\.id) == [keptDraft.id])
        #expect(!recordings.map(\.id).contains(deletedDraft.id))
    }

    @Test
    func recordingsRepairsFailedStatusWhenRequiredAudioFilesExistWithWarnings() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        try Data([1, 2, 3]).write(to: session.sourceURL.appendingPathComponent("mic.m4a"))
        try Data([4, 5, 6]).write(to: session.sourceURL.appendingPathComponent("system.m4a"))
        try Data([7, 8, 9]).write(to: session.exportURL.appendingPathComponent("mixed.m4a"))

        let draft = try store.stopSession(
            session,
            endedAt: Date(timeIntervalSince1970: 1_716_468_120),
            duration: 120,
            status: .failed,
            audioTracks: [
                AudioTrackMetadata(kind: "microphone", relativePath: "source/mic.m4a", durationSec: 120, fileSizeBytes: 3, status: "completed"),
                AudioTrackMetadata(
                    kind: "system",
                    relativePath: "source/system.m4a",
                    durationSec: 30,
                    fileSizeBytes: 3,
                    status: "failed",
                    error: "Failed to write system audio recording: ExtAudioFileWriteAsync failed with CoreAudio OSStatus -66570"
                ),
                AudioTrackMetadata(kind: "mixed", relativePath: "export/mixed.m4a", durationSec: 120, fileSizeBytes: 3, status: "completed")
            ]
        )

        let repaired = try #require(store.recordings(filters: RecordingListFilters()).first)
        let metadata = try store.readMetadata(at: draft.metadataURL)
        let systemTrack = try #require(metadata.audioTracks.first { $0.kind == "system" })

        #expect(repaired.status == .needsTagging)
        #expect(metadata.status == .needsTagging)
        #expect(systemTrack.status == "completed_with_warnings")
        #expect(systemTrack.error?.contains("OSStatus -66570") == true)
        #expect(metadata.qualityWarnings == ["System audio track ended before the recording stopped."])
        #expect(metadata.audio.health.status == .warning)
        #expect(metadata.audio.health.warnings == [.systemTrackTruncated])
    }

    @Test
    func recordingsAddsTruncatedSystemWarningToExistingMetadata() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        try Data([1, 2, 3]).write(to: session.sourceURL.appendingPathComponent("mic.m4a"))
        try Data([4, 5, 6]).write(to: session.sourceURL.appendingPathComponent("system.m4a"))
        try Data([7, 8, 9]).write(to: session.exportURL.appendingPathComponent("mixed.m4a"))

        let draft = try store.stopSession(
            session,
            endedAt: Date(timeIntervalSince1970: 1_716_468_420),
            duration: 420,
            status: .needsTagging,
            audioTracks: [
                AudioTrackMetadata(kind: "microphone", relativePath: "source/mic.m4a", durationSec: 420, fileSizeBytes: 3, status: "completed"),
                AudioTrackMetadata(kind: "system", relativePath: "source/system.m4a", durationSec: 170, fileSizeBytes: 3, status: "completed_with_warnings"),
                AudioTrackMetadata(kind: "mixed", relativePath: "export/mixed.m4a", durationSec: 420, fileSizeBytes: 3, status: "completed")
            ],
            audio: RecordingAudioMetadata(
                processing: .skipped,
                health: .good
            )
        )

        _ = try store.recordings(filters: RecordingListFilters())
        let metadata = try store.readMetadata(at: draft.metadataURL)

        #expect(metadata.qualityWarnings == ["System audio track ended before the recording stopped."])
        #expect(metadata.audio.health.status == .warning)
        #expect(metadata.audio.health.warnings == [.systemTrackTruncated])
    }

    @Test
    func updatesTitleTagsAndDeletesLocalRecord() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let draft = try store.stopSession(
            session,
            endedAt: Date(timeIntervalSince1970: 1_716_468_030),
            duration: 30,
            status: .needsTagging,
            audioTracks: []
        )

        try store.updateRecording(id: draft.id, title: "Updated title", tags: ["#разбор", "#важное"])
        let updated = try #require(store.recordings(filters: RecordingListFilters(titleText: "updated")).first)
        #expect(updated.title == "Updated title")
        #expect(updated.tags == ["#важное", "#разбор"])

        try store.deleteLocalRecord(updated)

        #expect(!FileManager.default.fileExists(atPath: updated.sessionFolderURL.path(percentEncoded: false)))
        #expect(try store.recordings(filters: RecordingListFilters()).isEmpty)
    }

    @Test
    func deleteLocalRecordRejectsSessionFolderOutsideStorageRoot() throws {
        let root = Self.testOutputFolder()
        let outsideFolder = Self.testOutputFolder()
            .deletingLastPathComponent()
            .appendingPathComponent("outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: outsideFolder,
            withIntermediateDirectories: true
        )

        let store = FileSystemRecordingStore(rootURL: root)
        let summary = RecordingSummary(
            id: "tampered",
            title: "Tampered",
            category: "",
            participant: "",
            tags: [],
            status: .needsTagging,
            sourceApp: "Zoom",
            startedAt: "2024-05-23T10:00:00Z",
            endedAt: "2024-05-23T10:01:00Z",
            durationSec: 60,
            metadataURL: outsideFolder.appendingPathComponent("metadata.json"),
            sessionFolderURL: outsideFolder
        )

        #expect(throws: FileSystemRecordingStoreError.pathOutsideStorageRoot) {
            try store.deleteLocalRecord(summary)
        }
        #expect(FileManager.default.fileExists(atPath: outsideFolder.path(percentEncoded: false)))
    }

    @Test
    func shortRecordingIsStoredInInboxShort() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )

        let draft = try store.stopSession(
            session,
            endedAt: Date(timeIntervalSince1970: 1_716_468_030),
            duration: 30,
            status: .needsTagging,
            audioTracks: []
        )

        #expect(draft.status == .shortRecording)
        #expect(draft.sessionFolderURL.path(percentEncoded: false).contains("Inbox/Short"))

        let metadata = try store.readMetadata(at: draft.metadataURL)
        #expect(metadata.status == .shortRecording)

        let indexed = try #require(store.recordings(filters: RecordingListFilters(status: .shortRecording)).first)
        #expect(indexed.id == draft.id)
        #expect(indexed.sessionFolderURL == draft.sessionFolderURL)
    }

    @Test
    func latestRecordingSummaryIncludesStatusFolderAndFileSizes() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(
                appName: "Zoom",
                bundleID: "us.zoom.xos",
                trigger: "autostart",
                ruleID: "autostart.v2.zoom",
                confidence: "high",
                reason: "Zoom active with microphone activity."
            )
        )
        let endedAt = Date(timeIntervalSince1970: 1_716_468_120)

        let draft = try store.stopSession(
            session,
            endedAt: endedAt,
            duration: 120,
            status: .needsTagging,
            audioTracks: [
                AudioTrackMetadata(kind: "microphone", relativePath: "source/mic.m4a", fileSizeBytes: 11, status: "completed"),
                AudioTrackMetadata(kind: "system", relativePath: "source/system.m4a", fileSizeBytes: 22, status: "completed"),
                AudioTrackMetadata(kind: "mixed", relativePath: "export/mixed.m4a", fileSizeBytes: 33, status: "completed")
            ]
        )

        let latest = try #require(try store.latestRecordingSummary())
        #expect(latest.id == draft.id)
        #expect(latest.status == .needsTagging)
        #expect(latest.displayStatus == "Needs tag")
        #expect(latest.folderName == draft.sessionFolderURL.lastPathComponent)
        #expect(latest.durationSec == 120)
        #expect(latest.micFileSizeBytes == 11)
        #expect(latest.systemFileSizeBytes == 22)
        #expect(latest.mixedFileSizeBytes == 33)
        #expect(latest.mixedPreviewState == "Ready")
        #expect(latest.startConfidence == "high")
        #expect(latest.startReason == "Zoom active with microphone activity.")
    }

    @Test
    func appendsMarkersToMetadata() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let session = try store.startSession(
            startedAt: Date(timeIntervalSince1970: 1_716_468_000),
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        let draft = try store.stopSession(
            session,
            endedAt: Date(timeIntervalSince1970: 1_716_468_120),
            duration: 120,
            status: .needsTagging,
            audioTracks: []
        )
        let marker = RecordingMarker.make(
            kind: .conflict,
            elapsedTime: 42.9,
            createdAt: Date(timeIntervalSince1970: 1_716_468_042),
            id: "marker-conflict"
        )

        try store.appendMarkers([marker], to: draft)

        let metadata = try store.readMetadata(at: draft.metadataURL)
        #expect(metadata.markers == [marker])

        let json = try String(contentsOf: draft.metadataURL, encoding: .utf8)
        #expect(json.contains("\"markers\""))
        #expect(json.contains("\"time_sec\""))
        #expect(json.contains("\"Conflict\""))
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
