import Foundation
import Testing
@testable import RecnyCore

struct LocalRecordingDocumentsTests {
    @Test func importsTimedSRTAndMultilineText() throws {
        let segments = try LocalTranscriptParser.srt("1\n00:00:01,250 --> 00:00:03,000\nПервая строка\nПродолжение\n\n2\n00:00:04,000 --> 00:00:05,000\nВторая строка\n", duration: 6)
        #expect(segments.count == 2)
        #expect(segments[0].start == 1.25)
        #expect(segments[0].text == "Первая строка Продолжение")
        #expect(segments[1].id == "s2")
    }
    @Test func rejectsInvalidAndOutOfBoundsTimestamps() {
        #expect(throws: LocalDocumentError.self) { try LocalTranscriptParser.srt("1\n00:00:03,000 --> 00:00:02,000\nТекст", duration: 10) }
        #expect(throws: LocalDocumentError.self) { try LocalTranscriptParser.srt("1\n00:00:01,000 --> 00:00:12,000\nТекст", duration: 5) }
    }
    @Test func plainTextHasNoInventedTimestamps() throws {
        let s = try LocalTranscriptParser.plainText("Первый абзац\n\nВторой абзац")
        #expect(s.count == 2)
        #expect(s.allSatisfy { $0.start == nil && $0.end == nil })
    }
    @Test func fingerprintChangesEvenForSameSizeAudio() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.m4a")
        try Data("123".utf8).write(to: audio)
        let first = try LocalAudioIdentity.read(audio)
        try Data("124".utf8).write(to: audio)
        #expect(first != (try LocalAudioIdentity.read(audio)))
    }
    @Test func notesRejectNonexistentSourceReferences() throws {
        let s = [LocalTranscriptSegment(id: "s1", text: "Факт", start: 0, end: 1)]
        let notes = LocalStructuredNotes(model: "m", revision: "r", preset: .meeting, sections: [.init(title: "Итоги", items: [.init(text: "Факт", sourceIDs: ["missing"])])])
        #expect(throws: LocalDocumentError.self) { try notes.validate(segments: s) }
    }
    @Test func savingRegeneratedNotesPreservesEditedMarkdown() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingDocumentStore(sessionFolderURL: root)
        let s = [LocalTranscriptSegment(id: "s1", text: "Факт", start: 0, end: 1)]
        let notes = LocalStructuredNotes(model: "m", revision: "r", preset: .meeting, sections: [.init(title: "Итоги", items: [.init(text: "Факт", sourceIDs: ["s1"])])])
        try store.saveNotes(notes, segments: s)
        try store.saveEditedNotes("Моя правка")
        try store.saveNotes(notes, segments: s)
        let history = try FileManager.default.contentsOfDirectory(at: store.directory.appendingPathComponent("history"), includingPropertiesForKeys: nil)
        #expect(try history.contains { try String(contentsOf: $0, encoding: .utf8) == "Моя правка" })
        #expect(try store.loadNotesMarkdown()?.contains("Факт") == true)
    }
    @Test func invalidNotesDoNotReplaceGoodNotes() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingDocumentStore(sessionFolderURL: root)
        try store.saveEditedNotes("Сохранённая заметка")
        let invalid = LocalStructuredNotes(model: "m", revision: "r", preset: .meeting, sections: [.init(title: "Итоги", items: [.init(text: "Выдумка", sourceIDs: ["missing"])])])
        #expect(throws: LocalDocumentError.self) { try store.saveNotes(invalid, segments: []) }
        #expect(try store.loadNotesMarkdown() == "Сохранённая заметка")
    }
    @Test func refusesSymlinkTranscriptDirectory() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let outside = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: outside) }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("transcript"), withDestinationURL: outside)
        #expect(throws: LocalDocumentError.self) { try LocalRecordingDocumentStore(sessionFolderURL: root).saveEditedNotes("No") }
        #expect(try FileManager.default.contentsOfDirectory(atPath: outside.path).isEmpty)
    }
    @Test func malformedCacheCanBeExplicitlyRebuilt() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let store = LocalRecordingDocumentStore(sessionFolderURL: root)
        try store.prepare()
        try Data("{invalid".utf8).write(to: store.checkedURL("segments.json"))
        #expect(try LocalRecordingProcessor.cachedTranscript(store: store, mode: .transcript) == nil)
        #expect(try LocalRecordingProcessor.cachedTranscript(store: store, mode: .all) == nil)
        #expect(throws: LocalDocumentError.self) { try LocalRecordingProcessor.cachedTranscript(store: store, mode: .notes) }
    }
    @Test func retranscriptionOfSameAudioInvalidatesOldNoteReferences() throws {
        let root = try temporaryFolder(); defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("audio.m4a")
        try Data("audio".utf8).write(to: audio)
        let identity = try LocalAudioIdentity.read(audio)
        let original = LocalRecordingTranscript(source: identity, segments: [.init(id: "s1", text: "Первый", start: 0, end: 1)])
        let revised = LocalRecordingTranscript(source: identity, segments: [.init(id: "s1", text: "Другой", start: 1, end: 2)])
        let store = LocalRecordingDocumentStore(sessionFolderURL: root)
        var notes = LocalStructuredNotes(model: "m", revision: "r", preset: .meeting, sections: [.init(title: "Итог", items: [.init(text: "Первый", sourceIDs: ["s1"])])])
        notes.source = identity
        try store.saveNotes(notes, segments: original.segments)
        let saved = try store.loadNotes()
        #expect(LocalDocumentFreshness.referencesAreCurrent(transcript: original, notes: saved, currentAudio: identity))
        #expect(!LocalDocumentFreshness.referencesAreCurrent(transcript: revised, notes: saved, currentAudio: identity))
        #expect(!LocalDocumentFreshness.referencesAreCurrent(transcript: original, notes: saved, currentAudio: nil))
    }
    private func temporaryFolder() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }
}
