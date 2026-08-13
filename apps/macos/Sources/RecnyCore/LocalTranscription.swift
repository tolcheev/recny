import Foundation

public enum LocalTranscriptionProvider: String, Codable, CaseIterable, Sendable {
    case parakeetMLX = "parakeet-mlx"
    case whisperKitCLI = "whisperkit-cli"

    public var displayName: String {
        switch self {
        case .parakeetMLX:
            return "parakeet-mlx"
        case .whisperKitCLI:
            return "WhisperKit CLI"
        }
    }
}

public struct LocalTranscriptionArtifactPaths: Equatable, Sendable {
    public let folderURL: URL
    public let textURL: URL
    public let srtURL: URL
    public let vttURL: URL
    public let jsonURL: URL
    public let noteMarkdownURL: URL

    public init(sessionFolderURL: URL) {
        self.folderURL = sessionFolderURL.appendingPathComponent("transcript", isDirectory: true)
        self.textURL = folderURL.appendingPathComponent("transcript.txt")
        self.srtURL = folderURL.appendingPathComponent("transcript.srt")
        self.vttURL = folderURL.appendingPathComponent("transcript.vtt")
        self.jsonURL = folderURL.appendingPathComponent("transcript.json")
        self.noteMarkdownURL = folderURL.appendingPathComponent("call_note.md")
    }
}

public struct LocalTranscriptionResult: Equatable, Sendable {
    public let provider: LocalTranscriptionProvider
    public let audioURL: URL
    public let paths: LocalTranscriptionArtifactPaths

    public init(
        provider: LocalTranscriptionProvider,
        audioURL: URL,
        paths: LocalTranscriptionArtifactPaths
    ) {
        self.provider = provider
        self.audioURL = audioURL
        self.paths = paths
    }
}

public enum LocalTranscriptionError: Error, Equatable, CustomStringConvertible, Sendable {
    case noUsableAudio
    case noLocalTranscriptionToolInstalled
    case parakeetMLXNotInstalled
    case whisperKitCLINotInstalled
    case ffmpegNotInstalled
    case modelNotPrepared
    case transcriptMissing(URL)
    case processFailed(provider: LocalTranscriptionProvider, status: Int32, output: String)

    public var description: String {
        switch self {
        case .noUsableAudio:
            return "No non-empty local audio file is available for transcription."
        case .noLocalTranscriptionToolInstalled:
            return "No local Parakeet transcription tool is installed. Open Settings -> Local Transcription and use: brew install uv ffmpeg && uv tool install parakeet-mlx -U"
        case .parakeetMLXNotInstalled:
            return "parakeet-mlx is not installed. Install it locally with: uv tool install parakeet-mlx -U"
        case .whisperKitCLINotInstalled:
            return "WhisperKit CLI is not installed. Install it locally with: brew install whisperkit-cli"
        case .ffmpegNotInstalled:
            return "ffmpeg is required by parakeet-mlx for m4a input. Install it with: brew install ffmpeg"
        case .modelNotPrepared:
            return "Local transcription is optional and is not prepared yet. Open Settings -> Local Transcription and prepare the Parakeet model first."
        case .transcriptMissing(let url):
            return "Transcription finished but transcript.txt was not created at \(url.path(percentEncoded: false))."
        case .processFailed(let provider, let status, let output):
            let trimmedOutput = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return "\(provider.displayName) failed with exit code \(status).\(trimmedOutput.isEmpty ? "" : " \(trimmedOutput)")"
        }
    }
}

public enum LocalTranscriptionSetupStatus: Equatable, Sendable {
    case missingTools([String])
    case needsModelDownload
    case ready(LocalTranscriptionProvider)

    public var canTranscribeWithoutSetup: Bool {
        if case .ready = self {
            return true
        }
        return false
    }

    public var displayText: String {
        switch self {
        case .missingTools(let tools):
            return "Not installed: \(tools.joined(separator: ", "))"
        case .needsModelDownload:
            return "Parakeet is installed. Model download is required."
        case .ready(let provider):
            return "\(provider.displayName) is ready."
        }
    }

    public var actionHint: String {
        switch self {
        case .missingTools:
            return "Install optional tools first: brew install uv ffmpeg && uv tool install parakeet-mlx -U"
        case .needsModelDownload:
            return "Use Settings to prepare the Parakeet model before transcribing from Records."
        case .ready:
            return "Records can transcribe locally without first-run downloads."
        }
    }
}

public enum LocalTranscriptionSetupInspector {
    private static let parakeetModelCachePath =
        "hub/models--mlx-community--parakeet-tdt-0.6b-v3/snapshots"

    public static func status(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LocalTranscriptionSetupStatus {
        let searchPaths = executableSearchPaths(environment: environment)
        let missingTools = ["parakeet-mlx", "ffmpeg"].filter {
            executableURL(named: $0, searchPaths: searchPaths, fileManager: fileManager) == nil
        }

        guard missingTools.isEmpty else {
            return .missingTools(missingTools)
        }

        guard parakeetModelIsCached(fileManager: fileManager, environment: environment) else {
            return .needsModelDownload
        }

        return .ready(.parakeetMLX)
    }

    public static func parakeetModelIsCached(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        let snapshotsURL = huggingFaceCacheURL(environment: environment)
            .appendingPathComponent(parakeetModelCachePath, isDirectory: true)

        guard let snapshotURLs = try? fileManager.contentsOfDirectory(
            at: snapshotsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }

        return snapshotURLs.contains { snapshotURL in
            let modelURL = snapshotURL.appendingPathComponent("model.safetensors")
            let configURL = snapshotURL.appendingPathComponent("config.json")
            return (try? modelURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) ?? 0 > 0
                && fileManager.fileExists(atPath: configURL.path(percentEncoded: false))
        }
    }

    public static func executableURL(
        named name: String,
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        executableURL(
            named: name,
            searchPaths: executableSearchPaths(environment: environment),
            fileManager: fileManager
        )
    }

    public static func executableSearchPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
        var paths: [String] = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]

        if let home = environment["HOME"], !home.isEmpty {
            paths.append("\(home)/.local/bin")
            paths.append("\(home)/.local/share/uv/tools/parakeet-mlx/bin")
        }

        if let path = environment["PATH"] {
            paths.append(contentsOf: path.split(separator: ":").map(String.init))
        }

        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }

    public static func huggingFaceCacheURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        if let hfHome = environment["HF_HOME"], !hfHome.isEmpty {
            return URL(fileURLWithPath: hfHome, isDirectory: true)
        }

        let home = environment["HOME"] ?? FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false)
        return URL(fileURLWithPath: home, isDirectory: true)
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
    }

    private static func executableURL(
        named name: String,
        searchPaths: [String],
        fileManager: FileManager
    ) -> URL? {
        for directory in searchPaths {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }

        return nil
    }
}

public enum LocalTranscriptionNoteFormatter {
    public static func markdown(
        recording: RecordingSummary,
        provider: LocalTranscriptionProvider,
        audioURL: URL,
        transcriptText: String,
        generatedAt: Date = Date()
    ) -> String {
        let generatedAtText = iso8601(generatedAt)
        let title = recording.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || recording.title == "Untitled recording"
            ? "Call Note"
            : recording.title
        let participant = recording.participant.trimmingCharacters(in: .whitespacesAndNewlines)
        let tags = recording.tags.isEmpty ? "none" : recording.tags.joined(separator: ", ")
        let cleanTranscript = transcriptText.trimmingCharacters(in: .whitespacesAndNewlines)

        return """
        # \(title)

        ## Metadata

        - Recording ID: \(recording.id)
        - Source: \(recording.sourceApp)
        - Started: \(recording.startedAt)
        - Duration: \(RecordingDisplayFormatter.duration(recording.durationSec))
        - Participant: \(participant.isEmpty ? "none" : participant)
        - Tags: \(tags)
        - Provider: \(provider.displayName)
        - Audio: \(audioURL.path(percentEncoded: false))
        - Generated: \(generatedAtText)

        ## Codex Review Prompt

        Проведи ЖОСКОЕ ревью созвона по транскрипту ниже. Найди:
        - цель созвона и фактический результат;
        - ключевые договоренности, вопросы и риски;
        - слабые места в коммуникации;
        - моменты, где нужно было уточнить или дожать;
        - конкретные follow-up задачи;
        - краткое executive summary.

        ## Transcript

        \(cleanTranscript.isEmpty ? "_Transcript is empty._" : cleanTranscript)
        """
    }

    private static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public final class LocalTranscriptionRunner: @unchecked Sendable {
    private let fileManager: FileManager
    private let environment: [String: String]

    public init(
        fileManager: FileManager = .default,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        self.fileManager = fileManager
        self.environment = environment
    }

    public func transcribe(
        recording: RecordingSummary,
        audioURL: URL
    ) async throws -> LocalTranscriptionResult {
        let setupStatus = LocalTranscriptionSetupInspector.status(
            fileManager: fileManager,
            environment: environment
        )
        if !setupStatus.canTranscribeWithoutSetup {
            switch setupStatus {
            case .missingTools(let tools):
                if tools.contains("parakeet-mlx") {
                    throw LocalTranscriptionError.parakeetMLXNotInstalled
                }
                throw LocalTranscriptionError.ffmpegNotInstalled
            case .needsModelDownload:
                throw LocalTranscriptionError.modelNotPrepared
            case .ready:
                break
            }
        }

        if executableURL(named: "parakeet-mlx") != nil {
            return try await transcribeWithParakeetMLX(recording: recording, audioURL: audioURL)
        }

        throw LocalTranscriptionError.noLocalTranscriptionToolInstalled
    }

    public func transcribeWithParakeetMLX(
        recording: RecordingSummary,
        audioURL: URL
    ) async throws -> LocalTranscriptionResult {
        guard let parakeetURL = executableURL(named: "parakeet-mlx") else {
            throw LocalTranscriptionError.parakeetMLXNotInstalled
        }
        guard executableURL(named: "ffmpeg") != nil else {
            throw LocalTranscriptionError.ffmpegNotInstalled
        }

        let paths = LocalTranscriptionArtifactPaths(sessionFolderURL: recording.sessionFolderURL)
        try fileManager.createDirectory(at: paths.folderURL, withIntermediateDirectories: true)

        try await runProcess(
            executableURL: parakeetURL,
            arguments: [
                audioURL.path(percentEncoded: false),
                "--output-dir", paths.folderURL.path(percentEncoded: false),
                "--output-format", "all",
                "--output-template", "transcript",
                "--chunk-duration", "120",
                "--overlap-duration", "15"
            ],
            provider: .parakeetMLX
        )

        guard fileManager.fileExists(atPath: paths.textURL.path(percentEncoded: false)) else {
            throw LocalTranscriptionError.transcriptMissing(paths.textURL)
        }

        let transcriptText = try String(contentsOf: paths.textURL, encoding: .utf8)
        let note = LocalTranscriptionNoteFormatter.markdown(
            recording: recording,
            provider: .parakeetMLX,
            audioURL: audioURL,
            transcriptText: transcriptText
        )
        try note.write(to: paths.noteMarkdownURL, atomically: true, encoding: .utf8)

        AppLogger.file(.info, category: "transcription", "created local transcript recording_id=\(recording.id) provider=parakeet-mlx audio=\(audioURL.path(percentEncoded: false)) note=\(paths.noteMarkdownURL.path(percentEncoded: false))")
        return LocalTranscriptionResult(
            provider: .parakeetMLX,
            audioURL: audioURL,
            paths: paths
        )
    }

    public func transcribeWithWhisperKitCLI(
        recording: RecordingSummary,
        audioURL: URL
    ) async throws -> LocalTranscriptionResult {
        guard let cliURL = executableURL(named: "argmax-cli") ?? executableURL(named: "whisperkit-cli") else {
            throw LocalTranscriptionError.whisperKitCLINotInstalled
        }

        let paths = LocalTranscriptionArtifactPaths(sessionFolderURL: recording.sessionFolderURL)
        try fileManager.createDirectory(at: paths.folderURL, withIntermediateDirectories: true)

        let output = try await runProcessCapturingOutput(
            executableURL: cliURL,
            arguments: [
                "transcribe",
                "--audio-path", audioURL.path(percentEncoded: false)
            ],
            provider: .whisperKitCLI
        )
        let transcriptText = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !transcriptText.isEmpty else {
            throw LocalTranscriptionError.transcriptMissing(paths.textURL)
        }

        try transcriptText.write(to: paths.textURL, atomically: true, encoding: .utf8)
        let note = LocalTranscriptionNoteFormatter.markdown(
            recording: recording,
            provider: .whisperKitCLI,
            audioURL: audioURL,
            transcriptText: transcriptText
        )
        try note.write(to: paths.noteMarkdownURL, atomically: true, encoding: .utf8)

        AppLogger.file(.info, category: "transcription", "created local transcript recording_id=\(recording.id) provider=whisperkit-cli audio=\(audioURL.path(percentEncoded: false)) note=\(paths.noteMarkdownURL.path(percentEncoded: false))")
        return LocalTranscriptionResult(
            provider: .whisperKitCLI,
            audioURL: audioURL,
            paths: paths
        )
    }

    public func prepareParakeetModel() async throws {
        guard let parakeetURL = executableURL(named: "parakeet-mlx") else {
            throw LocalTranscriptionError.parakeetMLXNotInstalled
        }
        guard executableURL(named: "ffmpeg") != nil else {
            throw LocalTranscriptionError.ffmpegNotInstalled
        }

        let workingFolder = fileManager.temporaryDirectory
            .appendingPathComponent("torbit-parakeet-setup-\(UUID().uuidString)", isDirectory: true)
        let outputFolder = workingFolder.appendingPathComponent("out", isDirectory: true)
        let audioURL = workingFolder.appendingPathComponent("setup.wav")
        try fileManager.createDirectory(at: outputFolder, withIntermediateDirectories: true)
        try writeSilentWAV(to: audioURL)
        defer {
            try? fileManager.removeItem(at: workingFolder)
        }

        try await runProcess(
            executableURL: parakeetURL,
            arguments: [
                audioURL.path(percentEncoded: false),
                "--output-dir", outputFolder.path(percentEncoded: false),
                "--output-format", "txt",
                "--output-template", "setup",
                "--chunk-duration", "0"
            ],
            provider: .parakeetMLX
        )

        guard LocalTranscriptionSetupInspector.status(
            fileManager: fileManager,
            environment: environment
        ).canTranscribeWithoutSetup else {
            throw LocalTranscriptionError.modelNotPrepared
        }
    }

    private func runProcess(
        executableURL: URL,
        arguments: [String],
        provider: LocalTranscriptionProvider
    ) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = processEnvironment()

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(
                        throwing: LocalTranscriptionError.processFailed(
                            provider: provider,
                            status: process.terminationStatus,
                            output: output
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: LocalTranscriptionError.processFailed(
                        provider: provider,
                        status: -1,
                        output: String(describing: error)
                    )
                )
            }
        }
    }

    private func runProcessCapturingOutput(
        executableURL: URL,
        arguments: [String],
        provider: LocalTranscriptionProvider
    ) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executableURL
            process.arguments = arguments
            process.environment = processEnvironment()

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = outputPipe

            process.terminationHandler = { process in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(
                        throwing: LocalTranscriptionError.processFailed(
                            provider: provider,
                            status: process.terminationStatus,
                            output: output
                        )
                    )
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(
                    throwing: LocalTranscriptionError.processFailed(
                        provider: provider,
                        status: -1,
                        output: String(describing: error)
                    )
                )
            }
        }
    }

    private func executableURL(named name: String) -> URL? {
        for directory in executableSearchPaths() {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(name)
            if fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) {
                return url
            }
        }

        return nil
    }

    private func executableSearchPaths() -> [String] {
        LocalTranscriptionSetupInspector.executableSearchPaths(environment: environment)
    }

    private func processEnvironment() -> [String: String] {
        var result = environment
        result["PATH"] = executableSearchPaths().joined(separator: ":")
        return result
    }

    private func writeSilentWAV(to url: URL) throws {
        let sampleRate = 16_000
        let channels = 1
        let bitsPerSample = 16
        let durationSamples = sampleRate / 2
        let bytesPerSample = bitsPerSample / 8
        let dataByteCount = durationSamples * channels * bytesPerSample
        let byteRate = sampleRate * channels * bytesPerSample
        let blockAlign = channels * bytesPerSample

        var data = Data()
        data.append(contentsOf: "RIFF".utf8)
        data.appendLittleEndianUInt32(UInt32(36 + dataByteCount))
        data.append(contentsOf: "WAVE".utf8)
        data.append(contentsOf: "fmt ".utf8)
        data.appendLittleEndianUInt32(16)
        data.appendLittleEndianUInt16(1)
        data.appendLittleEndianUInt16(UInt16(channels))
        data.appendLittleEndianUInt32(UInt32(sampleRate))
        data.appendLittleEndianUInt32(UInt32(byteRate))
        data.appendLittleEndianUInt16(UInt16(blockAlign))
        data.appendLittleEndianUInt16(UInt16(bitsPerSample))
        data.append(contentsOf: "data".utf8)
        data.appendLittleEndianUInt32(UInt32(dataByteCount))
        data.append(Data(repeating: 0, count: dataByteCount))
        try data.write(to: url, options: .atomic)
    }
}

private extension Data {
    mutating func appendLittleEndianUInt16(_ value: UInt16) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }

    mutating func appendLittleEndianUInt32(_ value: UInt32) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
