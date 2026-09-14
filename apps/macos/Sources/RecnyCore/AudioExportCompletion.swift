import Foundation

/// Bounds a stalled AVFoundation callback without limiting a progressing export.
/// All mutable state is protected by `lock`; callbacks may arrive on any queue.
final class AudioExportCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private var lastProgress = ProcessInfo.processInfo.systemUptime
    private var timer: DispatchSourceTimer?
    private let stallTimeout: TimeInterval
    private let continuation: CheckedContinuation<Void, Error>

    init(continuation: CheckedContinuation<Void, Error>, stallTimeout: TimeInterval = 60) {
        self.continuation = continuation
        self.stallTimeout = stallTimeout
    }

    var isFinished: Bool { lock.withLock { didFinish } }

    func recordProgress() {
        lock.withLock { lastProgress = ProcessInfo.processInfo.systemUptime }
    }

    func startMonitoring(onStall: @escaping @Sendable () -> Void) {
        let timer = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
        timer.schedule(deadline: .now() + stallTimeout, repeating: min(1, stallTimeout))
        // Retain the continuation even if AVFoundation drops its callback.
        // finish() cancels and releases the timer, breaking this ownership cycle.
        timer.setEventHandler {
            let error = RecordingControllerError.mixedAudioWriteFailed(
                "Audio export made no progress for \(self.stallTimeout) seconds; source audio is preserved"
            )
            // Claim completion before requesting cancellation so late callbacks
            // cannot report success or resume the continuation a second time.
            self.finish(.failure(error), onlyIfStalled: true, beforeResume: {
                AppLogger.file(.error, category: "recording", "\(error)")
                onStall()
            })
        }
        lock.withLock {
            if didFinish {
                timer.cancel()
            } else {
                self.timer = timer
            }
            timer.resume()
        }
    }

    func finish(_ result: Result<Void, Error>, onlyIfStalled: Bool = false, beforeResume: () -> Void = {}) {
        let shouldResume = lock.withLock {
            guard !didFinish else { return false }
            if onlyIfStalled && ProcessInfo.processInfo.systemUptime - lastProgress < stallTimeout {
                return false
            }
            didFinish = true
            timer?.cancel()
            timer = nil
            return true
        }
        guard shouldResume else { return }
        beforeResume()
        continuation.resume(with: result)
    }
}
