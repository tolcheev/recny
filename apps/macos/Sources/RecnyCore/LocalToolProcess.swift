import Darwin
import Foundation

public enum LocalToolError: Error, Equatable, LocalizedError, Sendable {
    case unavailable, failed(Int32), timedOut, outputTooLarge
    public var errorDescription: String? {
        switch self {
        case .unavailable: "The local helper could not start. Check local AI setup."
        case .failed(let status): "Local processing failed (exit \(status)). Check model setup and retry."
        case .timedOut: "Local processing exceeded its time limit. Try a shorter recording."
        case .outputTooLarge: "The local helper returned too much diagnostic output."
        }
    }
}

public enum LocalToolProcess {
    public static func run(
        executable: URL, arguments: [String], environment: [String: String] = ProcessInfo.processInfo.environment,
        workingDirectory: URL? = nil, timeout: TimeInterval = 3600
    ) async throws -> Data {
        let state = ProcessState()
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .utility).async {
                    do {
                        let process = Process()
                        process.executableURL = executable; process.arguments = arguments; process.environment = environment
                        process.currentDirectoryURL = workingDirectory
                        process.standardInput = FileHandle.nullDevice
                        let pipe = Pipe()
                        process.standardOutput = pipe
                        // Helpers may print audio/text in diagnostics. Never capture or log stderr.
                        process.standardError = FileHandle.nullDevice
                        try state.start(process)
                        let captured = BoundedProcessOutput()
                        let drained = DispatchSemaphore(value: 0)
                        DispatchQueue.global(qos: .utility).async {
                            captured.drain(pipe.fileHandleForReading, process: process, state: state)
                            drained.signal()
                        }
                        let timer = DispatchWorkItem { state.stop(.timeout) }
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + timeout, execute: timer)
                        process.waitUntilExit()
                        // Keep timeout active until inherited stdout has also finished.
                        drained.wait()
                        timer.cancel()
                        pipe.fileHandleForReading.closeFile()
                        pipe.fileHandleForWriting.closeFile()
                        try state.checkResult()
                        guard process.terminationStatus == 0 else { throw LocalToolError.failed(process.terminationStatus) }
                        continuation.resume(returning: captured.data)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        } onCancel: { state.stop(.cancellation) }
    }
}

private final class ProcessState: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false
    private var timeout = false
    private var overflow = false
    enum StopReason { case cancellation, timeout, outputOverflow }
    func start(_ newProcess: Process) throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        process = newProcess
        do { try newProcess.run() } catch { throw LocalToolError.unavailable }
    }
    func stop(_ reason: StopReason) {
        lock.lock()
        switch reason { case .timeout: timeout = true; case .cancellation: cancelled = true; case .outputOverflow: overflow = true }
        let running = process
        if let running, running.isRunning { running.terminate() }
        lock.unlock()
        // A helper can ignore SIGTERM. Do not let cancellation hold the queue forever.
        if let running {
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2) {
                if running.isRunning { kill(running.processIdentifier, SIGKILL) }
            }
        }
    }
    func checkResult() throws {
        lock.lock(); defer { lock.unlock() }
        if cancelled { throw CancellationError() }
        if overflow { throw LocalToolError.outputTooLarge }
        if timeout { throw LocalToolError.timedOut }
    }
}

private final class BoundedProcessOutput: @unchecked Sendable {
    // Only the draining worker mutates this; the waiting worker reads after its semaphore.
    private(set) var data = Data()
    func drain(_ handle: FileHandle, process: Process, state: ProcessState) {
        let limit = 8_000_000
        var exceeded = false
        var exitedAt: TimeInterval?
        var buffer = [UInt8](repeating: 0, count: 65_536)
        while true {
            if !process.isRunning {
                let now = ProcessInfo.processInfo.systemUptime
                if let exitedAt, now - exitedAt > 0.25 {
                    state.stop(.timeout)
                    return
                }
                if exitedAt == nil { exitedAt = now }
            }
            var descriptor = pollfd(fd: handle.fileDescriptor, events: Int16(POLLIN | POLLHUP), revents: 0)
            let count = poll(&descriptor, 1, 100)
            if count > 0 {
                // Foundation's read(upToCount:) can wait to fill its buffer on pipes.
                // POSIX read returns currently available bytes after poll.
                let size = Darwin.read(handle.fileDescriptor, &buffer, buffer.count)
                guard size > 0 else { return }
                if !exceeded {
                    if size > limit - data.count {
                        exceeded = true
                        state.stop(.outputOverflow)
                    } else { data.append(contentsOf: buffer.prefix(size)) }
                }
            } else if !process.isRunning || count < 0 { return }
        }
    }
}
