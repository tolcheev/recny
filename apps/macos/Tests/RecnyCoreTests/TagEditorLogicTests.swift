import Foundation
import Testing
@testable import RecnyCore

struct TagEditorLogicTests {
    @Test
    func exposesMVPQuickTagsForTagDialog() {
        #expect(MVPTags.quick == [
            "#лид",
            "#скрининг",
            "#интервью",
            "#важное"
        ])
    }

    @Test
    func togglesQuickTagWithoutDuplicates() {
        #expect(TagEditorLogic.toggled("#лид", in: []) == ["#лид"])
        #expect(TagEditorLogic.toggled("#лид", in: ["#скрининг", "#лид"]) == ["#скрининг"])
    }

    @Test
    func normalizesCustomTags() {
        #expect(
            TagEditorLogic.normalizedCustomTags("лид, #ВАЖНОЕ плохой_звук, лид") == [
                "#лид",
                "#важное",
                "#плохой_звук"
            ]
        )
    }

    @Test
    func saveStatusPreservesTechnicalRecordingStatuses() {
        #expect(
            TagEditorLogic.resolvedSaveStatus(
                originalStatus: .failed,
                selectedStatus: .saved
            ) == .failed
        )
        #expect(
            TagEditorLogic.resolvedSaveStatus(
                originalStatus: .shortRecording,
                selectedStatus: .saved
            ) == .shortRecording
        )
        #expect(
            TagEditorLogic.resolvedSaveStatus(
                originalStatus: .needsTagging,
                selectedStatus: .saved
            ) == .saved
        )
        #expect(
            TagEditorLogic.resolvedSaveStatus(
                originalStatus: .reviewed,
                selectedStatus: .needsReview
            ) == .needsReview
        )
    }

    @Test
    func saveDraftNormalizesTagsInMetadataAndSQLite() throws {
        let root = Self.testOutputFolder()
        let store = FileSystemRecordingStore(rootURL: root)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)
        let session = try store.startSession(
            startedAt: startedAt,
            source: RecordingSource(appName: "Zoom", bundleID: "us.zoom.xos")
        )
        var draft = try store.stopSession(
            session,
            endedAt: startedAt.addingTimeInterval(90),
            duration: 90,
            status: .needsTagging,
            audioTracks: []
        )

        draft.title = "Lead call"
        draft.participant = "Ivan"
        draft.tags = ["лид", "#ВАЖНОЕ", "лид"]
        draft.status = .needsReview
        try store.saveDraft(draft)

        let metadata = try store.readMetadata(at: draft.metadataURL)
        #expect(metadata.tags == ["#лид", "#важное"])
        #expect(metadata.status == .needsReview)

        let filtered = try store.recordings(filters: RecordingListFilters(tags: ["#важное"]))
        #expect(filtered.map(\.id).contains(draft.id))
    }

    private static func testOutputFolder() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("tag-editor-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
