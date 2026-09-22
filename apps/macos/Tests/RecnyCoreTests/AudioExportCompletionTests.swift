import Foundation
import Testing
@testable import RecnyCore

struct AudioExportCompletionTests {
    @Test
    func missingWriterCallbackTimesOutAndIgnoresLateSuccess() async {
        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion = AudioExportCompletion(continuation: continuation, stallTimeout: 0.03)
                completion.startMonitoring(onStall: {})
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.15) {
                    completion.finish(.success(()))
                }
            }
            Issue.record("A writer that never calls back must fail instead of waiting forever")
        } catch {
            #expect(String(describing: error).contains("no progress"))
        }
        // Let a late AVFoundation callback arrive; it must not resume twice.
        try? await Task.sleep(for: .milliseconds(180))
    }

    @Test
    func droppedWriterCallbackStillTimesOut() async {
        await #expect(throws: RecordingControllerError.self) {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let completion = AudioExportCompletion(continuation: continuation, stallTimeout: 0.03)
                completion.startMonitoring(onStall: {})
                // No writer callback retains completion beyond this scope.
            }
        }
    }

    @Test
    func progressExtendsDeadlineForLongExport() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = AudioExportCompletion(continuation: continuation, stallTimeout: 0.2)
            completion.startMonitoring(onStall: {})
            for index in 1...8 {
                DispatchQueue.global().asyncAfter(deadline: .now() + Double(index) * 0.05) {
                    completion.recordProgress()
                    if index == 8 { completion.finish(.success(())) }
                }
            }
        }
    }

    @Test
    func completionCancelsWatchdog() async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let completion = AudioExportCompletion(continuation: continuation, stallTimeout: 0.03)
            completion.startMonitoring(onStall: { Issue.record("Completed export was cancelled") })
            completion.finish(.success(()))
        }
        try await Task.sleep(for: .milliseconds(100))
    }
}
