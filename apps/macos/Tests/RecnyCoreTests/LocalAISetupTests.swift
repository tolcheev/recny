import Foundation
import Testing
@testable import RecnyCore

struct LocalAISetupTests {
    @Test func cancellationDuringStatusRemainsCancellation() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let runtime = root.appendingPathComponent("runtime/bin")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let python = runtime.appendingPathComponent("python3")
        try "#!/bin/sh\nif [ \"$2\" = status ]; then exec /bin/sleep 30; fi\nexit 0\n".write(to: python, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: python.path)
        let task = Task { try await LocalAISetup(baseURL: root).prepareNotesModel() }
        try await Task.sleep(for: .milliseconds(150))
        task.cancel()
        do { try await task.value; Issue.record("Expected cancellation") }
        catch is CancellationError { }
    }
}
