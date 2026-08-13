import Foundation
import Testing
@testable import RecnyCore

struct LibraryRecordingFilterTests {
    @Test
    func searchMatchesTitleParticipantTagsAndSource() {
        let recording = RecordingSummary(
            id: "rec_1",
            title: "Lead follow-up call",
            category: "lead",
            participant: "Ivan Petrov",
            tags: ["#лид", "#важное"],
            status: .saved,
            sourceApp: "Zoom",
            startedAt: "2026-05-24T10:15:00Z",
            endedAt: "2026-05-24T10:45:00Z",
            durationSec: 1_800,
            metadataURL: URL(fileURLWithPath: "/tmp/metadata.json"),
            sessionFolderURL: URL(fileURLWithPath: "/tmp/recording")
        )

        #expect(LibraryRecordingFilter.matches(recording, query: "lead"))
        #expect(LibraryRecordingFilter.matches(recording, query: "ivan"))
        #expect(LibraryRecordingFilter.matches(recording, query: "#важное"))
        #expect(LibraryRecordingFilter.matches(recording, query: "zoom"))
        #expect(!LibraryRecordingFilter.matches(recording, query: "chrome"))
    }

    @Test
    func dateRangeFiltersByStartedAt() {
        let recording = RecordingSummary(
            id: "rec_2",
            title: "Interview",
            category: "interview",
            participant: "",
            tags: [],
            status: .needsReview,
            sourceApp: "Google Chrome",
            startedAt: "2026-05-22T20:30:00Z",
            endedAt: "2026-05-22T21:00:00Z",
            durationSec: 1_800,
            metadataURL: URL(fileURLWithPath: "/tmp/metadata.json"),
            sessionFolderURL: URL(fileURLWithPath: "/tmp/recording")
        )

        #expect(LibraryRecordingFilter.matches(recording, dateFromText: "2026-05-22", dateToText: "2026-05-22"))
        #expect(LibraryRecordingFilter.matches(recording, dateFromText: "2026-05-21", dateToText: "2026-05-23"))
        #expect(!LibraryRecordingFilter.matches(recording, dateFromText: "2026-05-23", dateToText: ""))
        #expect(!LibraryRecordingFilter.matches(recording, dateFromText: "", dateToText: "2026-05-21"))
    }

    @Test
    func audioHealthFilterMatchesSelectedStatusOnly() {
        #expect(LibraryRecordingFilter.matchesAudioHealth(.good, selectedStatus: nil))
        #expect(LibraryRecordingFilter.matchesAudioHealth(.warning, selectedStatus: .warning))
        #expect(!LibraryRecordingFilter.matchesAudioHealth(.good, selectedStatus: .warning))
        #expect(!LibraryRecordingFilter.matchesAudioHealth(.failed, selectedStatus: .warning))
    }
}
