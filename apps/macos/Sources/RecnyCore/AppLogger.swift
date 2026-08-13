import Foundation
import OSLog

public enum FileLogLevel: String {
    case info = "INFO"
    case warning = "WARN"
    case error = "ERROR"
}

public final class FileLogStore: @unchecked Sendable {
    public let logDirectoryURL: URL
    public let logFileURL: URL
    public let archiveLogFileURL: URL
    public let maxFileSizeBytes: Int

    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter
    private let fileManager: FileManager

    public init(
        logsDirectoryURL: URL = RecordingPaths.defaultRoot.appendingPathComponent("logs", isDirectory: true),
        fileName: String = "app.log",
        archiveFileName: String = "app.1.log",
        maxFileSizeBytes: Int = 5 * 1024 * 1024,
        fileManager: FileManager = .default
    ) {
        self.logDirectoryURL = logsDirectoryURL
        self.logFileURL = logsDirectoryURL.appendingPathComponent(fileName)
        self.archiveLogFileURL = logsDirectoryURL.appendingPathComponent(archiveFileName)
        self.maxFileSizeBytes = max(1, maxFileSizeBytes)
        self.fileManager = fileManager
        self.dateFormatter = ISO8601DateFormatter()
        self.dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    }

    public func write(level: FileLogLevel, category: String, message: String) throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        let line = makeLine(level: level, category: category, message: message)
        try rotateIfNeeded(forIncomingByteCount: line.utf8.count)
        try append(line)
    }

    public func recentLines(limit: Int) throws -> [String] {
        lock.lock()
        defer { lock.unlock() }

        let boundedLimit = max(0, limit)
        guard boundedLimit > 0 else {
            return []
        }

        let archiveLines = try readLinesIfExists(at: archiveLogFileURL)
        let activeLines = try readLinesIfExists(at: logFileURL)
        return Array((archiveLines + activeLines).suffix(boundedLimit))
    }

    public func clear() throws {
        lock.lock()
        defer { lock.unlock() }

        try fileManager.createDirectory(at: logDirectoryURL, withIntermediateDirectories: true)
        try removeIfExists(at: logFileURL)
        try removeIfExists(at: archiveLogFileURL)
    }

    private func makeLine(level: FileLogLevel, category: String, message: String) -> String {
        let timestamp = dateFormatter.string(from: Date())
        let sanitizedCategory = sanitize(category)
        let sanitizedMessage = sanitize(message)
        return "\(timestamp) [\(level.rawValue)] [\(sanitizedCategory)] \(sanitizedMessage)\n"
    }

    private func sanitize(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func rotateIfNeeded(forIncomingByteCount incomingByteCount: Int) throws {
        guard fileManager.fileExists(atPath: logFileURL.path(percentEncoded: false)) else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: logFileURL.path(percentEncoded: false))
        let currentSize = attributes[.size] as? NSNumber
        let projectedSize = (currentSize?.intValue ?? 0) + incomingByteCount
        guard projectedSize > maxFileSizeBytes else {
            return
        }

        try removeIfExists(at: archiveLogFileURL)
        try fileManager.moveItem(at: logFileURL, to: archiveLogFileURL)
    }

    private func append(_ line: String) throws {
        let data = Data(line.utf8)
        if fileManager.fileExists(atPath: logFileURL.path(percentEncoded: false)) {
            let handle = try FileHandle(forWritingTo: logFileURL)
            defer {
                try? handle.close()
            }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: logFileURL, options: [.atomic])
        }
    }

    private func readLinesIfExists(at url: URL) throws -> [String] {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return []
        }

        let contents = try String(contentsOf: url, encoding: .utf8)
        return contents
            .split(whereSeparator: \.isNewline)
            .map(String.init)
    }

    private func removeIfExists(at url: URL) throws {
        guard fileManager.fileExists(atPath: url.path(percentEncoded: false)) else {
            return
        }

        try fileManager.removeItem(at: url)
    }
}

public enum AppLogger {
    public static let subsystem = "com.torbit.recorder"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let recording = Logger(subsystem: subsystem, category: "recording")
    public static let storage = Logger(subsystem: subsystem, category: "storage")
    private static let fileLogStoreLock = NSLock()
    private nonisolated(unsafe) static var currentFileLogStore = makeDefaultFileLogStore()

    public static var fileLogStore: FileLogStore {
        fileLogStoreLock.lock()
        defer {
            fileLogStoreLock.unlock()
        }

        return currentFileLogStore
    }

    public static func configureFileLogging(rootURL: URL) {
        configureFileLogging(
            logsDirectoryURL: rootURL.appendingPathComponent("logs", isDirectory: true)
        )
    }

    public static func configureFileLogging(logsDirectoryURL: URL) {
        fileLogStoreLock.lock()
        currentFileLogStore = FileLogStore(logsDirectoryURL: logsDirectoryURL)
        fileLogStoreLock.unlock()
    }

    public static func resetFileLoggingForTesting() {
        guard isRunningTests else {
            return
        }

        fileLogStoreLock.lock()
        currentFileLogStore = makeDefaultFileLogStore()
        fileLogStoreLock.unlock()
    }

    public static func file(_ level: FileLogLevel, category: String, _ message: @autoclosure () -> String) {
        do {
            try fileLogStore.write(level: level, category: category, message: message())
        } catch {
            app.error("Failed to write local file log: \(String(describing: error), privacy: .public)")
        }
    }

    private static func makeDefaultFileLogStore() -> FileLogStore {
        guard isRunningTests else {
            return FileLogStore()
        }

        let testLogsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecnyTestLogs-\(ProcessInfo.processInfo.processIdentifier)", isDirectory: true)
        return FileLogStore(logsDirectoryURL: testLogsDirectory)
    }

    private static var isRunningTests: Bool {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return true
        }

        return CommandLine.arguments.contains { argument in
            argument.contains(".xctest") || argument.contains("RecnyPackageTests")
        }
    }
}
