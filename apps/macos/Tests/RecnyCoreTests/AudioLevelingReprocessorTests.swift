import Foundation
import Testing
@testable import RecnyCore

@MainActor
struct AudioLevelingReprocessorTests {
    @Test
    func reprocessSingleRecordingCreatesBalancedAudioAndUpdatesMetadataIndex() async throws {
        let fixture = try await Self.makeRecordingFixture(includeMic: true, includeSystem: true)
        let reprocessor = AudioLevelingReprocessor(store: fixture.store)

        let result = try await reprocessor.reprocess(
            recording: fixture.summary,
            overwritePolicy: .skipExisting
        )

        #expect(result.status == .processed)
        #expect(Self.nonEmptyFile(fixture.sessionFolder.appendingPathComponent("export/mixed_balanced.m4a")))
        #expect(Self.nonEmptyFile(fixture.sessionFolder.appendingPathComponent("analysis/audio_analysis.json")))

        let metadata = try fixture.store.readMetadata(at: fixture.summary.metadataURL)
        #expect(metadata.audio.processing.balancedMixStatus == .done)
        #expect(metadata.audio.processing.balancedMixPath == "export/mixed_balanced.m4a")
        #expect(metadata.audio.processing.analysisPath == "analysis/audio_analysis.json")
        #expect(metadata.audio.health.status == .good)
        #expect(metadata.audioTracks.contains { $0.kind == "mixed_balanced" && $0.status == "completed" })

        let indexed = try fixture.store.recordings(filters: RecordingListFilters(titleText: "Old recording"))
        #expect(indexed.contains { $0.id == fixture.summary.id })
    }

    @Test
    func skipExistingBalancedAudioLeavesFileAndMetadataUnchanged() async throws {
        let fixture = try await Self.makeRecordingFixture(includeMic: true, includeSystem: true)
        let balancedURL = fixture.sessionFolder.appendingPathComponent("export/mixed_balanced.m4a")
        try Data("existing balanced placeholder".utf8).write(to: balancedURL)

        let beforeMetadata = try fixture.store.readMetadata(at: fixture.summary.metadataURL)
        let reprocessor = AudioLevelingReprocessor(store: fixture.store)

        let result = try await reprocessor.reprocess(
            recording: fixture.summary,
            overwritePolicy: .skipExisting
        )

        let afterMetadata = try fixture.store.readMetadata(at: fixture.summary.metadataURL)
        let fileContents = try Data(contentsOf: balancedURL)

        #expect(result.status == .skippedExisting)
        #expect(fileContents == Data("existing balanced placeholder".utf8))
        #expect(afterMetadata.audio.processing == beforeMetadata.audio.processing)
    }

    @Test
    func overwriteExistingBalancedAudioReplacesFileAndUpdatesMetadata() async throws {
        let fixture = try await Self.makeRecordingFixture(includeMic: true, includeSystem: false)
        let balancedURL = fixture.sessionFolder.appendingPathComponent("export/mixed_balanced.m4a")
        try Data("old".utf8).write(to: balancedURL)

        let reprocessor = AudioLevelingReprocessor(store: fixture.store)
        let result = try await reprocessor.reprocess(
            recording: fixture.summary,
            overwritePolicy: .overwriteExisting
        )

        let metadata = try fixture.store.readMetadata(at: fixture.summary.metadataURL)
        let size = try #require(Self.fileSize(balancedURL))

        #expect(result.status == .processed)
        #expect(size > 3)
        #expect(metadata.audio.processing.balancedMixStatus == .partial)
        #expect(metadata.audio.health.status == .warning)
        #expect(metadata.audio.health.warnings.contains(.onlyOneTrackAvailable))
    }

    @Test
    func missingSourceFilesFailGracefullyAndMarkMetadataFailed() async throws {
        let fixture = try await Self.makeRecordingFixture(includeMic: false, includeSystem: false)
        let reprocessor = AudioLevelingReprocessor(store: fixture.store)

        let result = try await reprocessor.reprocess(
            recording: fixture.summary,
            overwritePolicy: .overwriteExisting
        )

        let metadata = try fixture.store.readMetadata(at: fixture.summary.metadataURL)

        #expect(result.status == .failed)
        #expect(metadata.status == .failed)
        #expect(metadata.audio.processing.balancedMixStatus == .failed)
        #expect(metadata.audio.health.status == .failed)
        #expect(metadata.audio.health.warnings.contains(.balancedMixFailed))
        #expect(Self.nonEmptyFile(fixture.sessionFolder.appendingPathComponent("analysis/audio_analysis.json")))
    }

    private static func makeRecordingFixture(
        includeMic: Bool,
        includeSystem: Bool
    ) async throws -> RecordingFixture {
        let root = testRoot().appendingPathComponent(UUID().uuidString, isDirectory: true)
        let store = FileSystemRecordingStore(rootURL: root)
        try store.prepareRoot()

        let sessionFolder = root
            .appendingPathComponent("Library/2026/05", isDirectory: true)
            .appendingPathComponent("2026-05-24_12-00_torbitrecorder_audio", isDirectory: true)
        let sourceFolder = sessionFolder.appendingPathComponent("source", isDirectory: true)
        let exportFolder = sessionFolder.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportFolder, withIntermediateDirectories: true)

        if includeMic {
            try await makeM4A(at: sourceFolder.appendingPathComponent("mic.m4a"))
        }
        if includeSystem {
            try await makeM4A(at: sourceFolder.appendingPathComponent("system.m4a"))
        }

        let metadataURL = sessionFolder.appendingPathComponent("metadata.json")
        let metadata = RecordingMetadata(
            id: UUID().uuidString,
            title: "Old recording",
            startedAt: "2026-05-24T09:00:00Z",
            endedAt: "2026-05-24T09:01:00Z",
            durationSec: 1,
            audio: RecordingAudioMetadata(),
            audioTracks: [
                existingTrack(kind: "microphone", relativePath: "source/mic.m4a", folder: sessionFolder),
                existingTrack(kind: "system", relativePath: "source/system.m4a", folder: sessionFolder)
            ],
            status: .saved
        )
        try RecordingMetadataCodec().write(metadata, to: metadataURL)

        return RecordingFixture(
            store: store,
            summary: RecordingSummary(
                id: metadata.id,
                title: metadata.title,
                category: metadata.category,
                participant: "",
                tags: [],
                status: metadata.status,
                sourceApp: metadata.source.appName,
                startedAt: metadata.startedAt,
                endedAt: metadata.endedAt,
                durationSec: metadata.durationSec,
                metadataURL: metadataURL,
                sessionFolderURL: sessionFolder
            ),
            sessionFolder: sessionFolder
        )
    }

    private static func makeM4A(at outputURL: URL) async throws {
        let fixtureURL = URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
        let analysis = try AudioLevelAnalyzer().analyze(url: fixtureURL, kind: .microphone)
        let plan = AudioBalancePlan(
            microphoneGainDB: 0,
            systemGainDB: 0,
            limiterCeilingDBFS: -1,
            limiterRequired: false,
            status: .partial,
            usedSourceKinds: ["microphone"],
            warnings: []
        )
        _ = try await AudioBalancedMixer().createBalancedMix(
            micURL: fixtureURL,
            systemURL: outputURL.deletingLastPathComponent().appendingPathComponent("missing-system.m4a"),
            outputURL: outputURL,
            plan: plan
        )
        #expect(analysis.hasUsableSignal)
    }

    private static func existingTrack(
        kind: String,
        relativePath: String,
        folder: URL
    ) -> AudioTrackMetadata {
        let url = folder.appendingPathComponent(relativePath)
        let size = fileSize(url)
        return AudioTrackMetadata(
            kind: kind,
            relativePath: relativePath,
            fileSizeBytes: size,
            status: size == nil ? "missing" : "completed"
        )
    }

    private static func nonEmptyFile(_ url: URL) -> Bool {
        (fileSize(url) ?? 0) > 0
    }

    private static func fileSize(_ url: URL) -> Int64? {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber
        else {
            return nil
        }
        return size.int64Value
    }

    private static func testRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("audio-reprocessor-tests", isDirectory: true)
    }
}

private struct RecordingFixture {
    let store: FileSystemRecordingStore
    let summary: RecordingSummary
    let sessionFolder: URL
}
