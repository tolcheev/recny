import Foundation
import Testing
@testable import TOrbitRecorderCore

@MainActor
struct AppStateTests {
    @Test
    func startsAndStopsWithStubController() async throws {
        let controller = StubRecordingController()
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder()
        )

        try await appState.startRecording()

        #expect(appState.status == .recording)
        #expect(appState.micStatus == .ready)
        #expect(appState.systemAudioStatus == .ready)
        #expect(appState.currentRecordingDuration >= 0)

        try await appState.stopRecording()

        #expect(appState.status == .idle)
        #expect(appState.micStatus == .idle)
        #expect(appState.systemAudioStatus == .idle)
    }

    @Test
    func refusesDuplicateStart() async throws {
        let controller = StubRecordingController()
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder()
        )

        try await appState.startRecording()

        await #expect(throws: RecordingControllerError.alreadyRecording) {
            try await appState.startRecording()
        }
    }

    @Test
    func stopCreatesNeedsTaggingMetadata() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder
        )

        try await appState.startRecording()
        try await appState.stopRecording()

        let draft = try #require(appState.postCallDraft)
        #expect(draft.status == .needsTagging)
        #expect(appState.isPostCallPanelPresented)

        let metadataURL = draft.metadataURL
        #expect(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))

        let store = RecordingMetadataStore(rootURL: outputFolder)
        let recordings = try store.recordings(filterTag: nil)
        #expect(recordings.map(\.id).contains(draft.id))
        #expect(recordings.first(where: { $0.id == draft.id })?.status == .needsTagging)
    }

    @Test
    func savePostCallTagsToMetadataAndSQLite() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder
        )

        try await appState.startRecording()
        try await appState.stopRecording()

        var draft = try #require(appState.postCallDraft)
        draft.title = "Lead call follow-up"
        draft.category = "lead"
        draft.participant = "Ivan Lead"
        draft.tags = ["#лид", "#продажа"]
        draft.status = .saved

        try appState.savePostCallDraft(draft)

        let metadata = try RecordingMetadataStore(rootURL: outputFolder)
            .readMetadata(at: draft.metadataURL)
        #expect(metadata.title == "Lead call follow-up")
        #expect(metadata.category == "lead")
        #expect(metadata.participants == ["Ivan Lead"])
        #expect(metadata.tags == ["#лид", "#продажа"])
        #expect(metadata.status == .saved)

        let filtered = try RecordingMetadataStore(rootURL: outputFolder)
            .recordings(filterTag: "#лид")
        #expect(filtered.map(\.id).contains(draft.id))
    }

    private static func testOutputFolder() -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("test-recordings", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
