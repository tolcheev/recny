import Foundation
import Testing
@testable import RecnyCore

@MainActor
struct LocalProcessingCoordinatorTests {
    @Test func serializesJobsAndRejectsDuplicateRecording() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = ProcessingProbe()
        let coordinator = LocalProcessingCoordinator(processor: probe)
        let a = try request("a", root: root), b = try request("b", root: root)
        #expect(try coordinator.enqueue(a))
        #expect(try !coordinator.enqueue(a))
        #expect(try coordinator.enqueue(b))
        for _ in 0..<100 where coordinator.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(!coordinator.isBusy)
        #expect(await probe.maximum == 1)
        #expect(coordinator.jobs["a"]?.stage == .completed)
        #expect(coordinator.jobs["b"]?.stage == .completed)
    }
    @Test func cancellationFinishesBeforeNextJobStarts() async throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let probe = ProcessingProbe()
        let coordinator = LocalProcessingCoordinator(processor: probe)
        #expect(try coordinator.enqueue(request("a", root: root)))
        try await Task.sleep(for: .milliseconds(20))
        coordinator.cancel("a")
        for _ in 0..<100 where coordinator.isBusy { try await Task.sleep(for: .milliseconds(10)) }
        #expect(coordinator.jobs["a"]?.stage == .cancelled)
        #expect(await probe.active == 0)
    }
    @Test func restartMarksUnfinishedJobsInterrupted() throws {
        let root = try folder(); defer { try? FileManager.default.removeItem(at: root) }
        let req = try request("a", root: root)
        let saved = LocalProcessingJobState(recordingID: "a", stage: .analyzing, preset: .meeting, mode: .all)
        try LocalRecordingDocumentStore(sessionFolderURL: req.sessionFolderURL).write(saved, name: "processing.json")
        let coordinator = LocalProcessingCoordinator(processor: ProcessingProbe())
        try coordinator.restore(recordingID: "a", sessionFolderURL: req.sessionFolderURL)
        #expect(coordinator.jobs["a"]?.stage == .interrupted)
    }
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func request(_ id: String, root: URL) throws -> LocalProcessingRequest {
        let folder = root.appendingPathComponent(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return LocalProcessingRequest(recordingID: id, sessionFolderURL: folder, audioURL: folder.appendingPathComponent("audio.m4a"), storageRootURL: root, preset: .meeting, mode: .all)
    }
}
private actor ProcessingProbe: LocalRecordingProcessing {
    var active = 0
    var maximum = 0
    func process(_ request: LocalProcessingRequest, progress: @escaping @Sendable (LocalProcessingStage) async throws -> Void) async throws {
        active += 1; maximum = max(maximum, active)
        defer { active -= 1 }
        try await progress(.transcribing)
        try await Task.sleep(for: .milliseconds(70))
        try await progress(.analyzing)
        try await Task.sleep(for: .milliseconds(50))
    }
}
