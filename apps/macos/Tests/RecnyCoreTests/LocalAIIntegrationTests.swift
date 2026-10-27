import Foundation
import Testing
@testable import RecnyCore

/// Opt-in real inference. Audio stays local; no fixture content is logged.
struct LocalAIIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["RECNY_LOCAL_AI_SMOKE_AUDIO"] != nil))
    func processesRealAudioAndReusesTranscriptForNewNotes() async throws {
        let input = try #require(ProcessInfo.processInfo.environment["RECNY_LOCAL_AI_SMOKE_AUDIO"])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("recny-ai-integration-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent("recording")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        let audio = session.appendingPathComponent("audio.m4a")
        try FileManager.default.copyItem(at: URL(fileURLWithPath: input), to: audio)
        let request = LocalProcessingRequest(recordingID: "smoke", sessionFolderURL: session, audioURL: audio, storageRootURL: root, preset: .meeting, mode: .all)
        try await LocalRecordingProcessor().process(request) { _ in }
        let store = LocalRecordingDocumentStore(sessionFolderURL: session)
        let transcript = try #require(try store.loadTranscript())
        #expect(!transcript.segments.isEmpty)
        #expect(transcript.segments.contains { $0.text.range(of: "[А-Яа-яЁё]", options: .regularExpression) != nil })
        #expect(transcript.segments.allSatisfy { $0.start != nil })
        let notes = try #require(try store.loadNotes())
        try notes.validate(segments: transcript.segments)
        #expect(notes.source == transcript.source)
        #expect(try store.loadNotesMarkdown()?.isEmpty == false)
        let before = try store.read("segments.json")
        let notesOnly = LocalProcessingRequest(recordingID: "smoke", sessionFolderURL: session, audioURL: audio, storageRootURL: root, preset: .mentoring, mode: .notes)
        try await LocalRecordingProcessor().process(notesOnly) { stage in #expect(stage != .transcribing) }
        #expect(try store.read("segments.json") == before)
        #expect(try store.loadNotes()?.preset == .mentoring)
    }
}
