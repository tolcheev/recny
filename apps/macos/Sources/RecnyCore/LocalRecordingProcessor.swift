import AVFoundation
import Foundation

public struct LocalRecordingProcessor: LocalRecordingProcessing {
    public let setup: LocalAISetup
    public init(setup: LocalAISetup = LocalAISetup()) { self.setup = setup }
    static func cachedTranscript(store: LocalRecordingDocumentStore, mode: LocalProcessingMode) throws -> LocalRecordingTranscript? {
        if mode == .transcript { return nil }
        do { return try store.loadTranscript() }
        catch LocalDocumentError.unsafePath { throw LocalDocumentError.unsafePath }
        catch {
            if mode == .all { return nil }
            throw LocalDocumentError.missingTranscript
        }
    }
    public func process(_ request: LocalProcessingRequest, progress: @escaping @Sendable (LocalProcessingStage) async throws -> Void) async throws {
        try request.validatePaths()
        try Task.checkCancellation()
        let store = LocalRecordingDocumentStore(sessionFolderURL: request.sessionFolderURL)
        try store.prepare()
        let workspace = try store.checkedURL("work-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: workspace) }
        let identity = try LocalAudioIdentity.read(request.audioURL)
        let oldTranscript = try Self.cachedTranscript(store: store, mode: request.mode)
        var transcript: LocalRecordingTranscript
        if request.mode != .transcript, let existing = oldTranscript, existing.source == identity {
            transcript = existing
        } else {
            guard request.mode != .notes else { throw oldTranscript == nil ? LocalDocumentError.missingTranscript : .sourceChanged }
            try await progress(.transcribing)
            let modelURL = try setup.parakeetModelURL()
            guard let executable = LocalTranscriptionSetupInspector.executableURL(named: "parakeet-mlx", environment: setup.environment) else { throw LocalAISetupError.transcriptionSetupMissing }
            let duration = try await AVURLAsset(url: request.audioURL).load(.duration).seconds
            guard duration.isFinite, duration > 0 else { throw LocalDocumentError.invalidTranscript }
            _ = try await LocalToolProcess.run(executable: executable, arguments: [request.audioURL.path, "--model", modelURL.path, "--output-dir", workspace.path, "--output-format", "all", "--output-template", "transcript", "--chunk-duration", "120", "--overlap-duration", "15"], environment: setup.processEnvironment(), workingDirectory: workspace, timeout: max(3600, duration * 3))
            try Task.checkCancellation()
            let srtURL = workspace.appendingPathComponent("transcript.srt")
            let segments = try LocalTranscriptParser.srt(String(contentsOf: srtURL, encoding: .utf8), duration: duration)
            transcript = LocalRecordingTranscript(source: identity, segments: segments)
            guard try LocalAudioIdentity.read(request.audioURL) == identity else { throw LocalDocumentError.sourceChanged }
            var exports: [String: Data] = [:]
            for suffix in ["txt", "srt", "vtt", "json"] {
                let name = "transcript.\(suffix)"
                let url = workspace.appendingPathComponent(name)
                if FileManager.default.fileExists(atPath: url.path) { exports[name] = try Data(contentsOf: url) }
            }
            try request.validatePaths()
            try Task.checkCancellation()
            try store.saveTranscript(transcript, exports: exports)
        }
        guard request.mode != .transcript else { return }
        try await progress(.analyzing)
        let notesStatus = await setup.notesStatus()
        try Task.checkCancellation()
        guard notesStatus.ready else { throw LocalAISetupError.notesModelMissing }
        // JSONSerialization preserves explicit null timestamps in legacy documents.
        let segments: [[String: Any]] = transcript.segments.map { ["id": $0.id, "text": $0.text, "start": $0.start.map { $0 as Any } ?? NSNull(), "end": $0.end.map { $0 as Any } ?? NSNull()] }
        let input = workspace.appendingPathComponent("input.json"), output = workspace.appendingPathComponent("notes.json")
        let payload = try JSONSerialization.data(withJSONObject: ["segments": segments, "preset": request.preset.rawValue], options: [.sortedKeys])
        try payload.write(to: input, options: .atomic)
        _ = try await setup.runHelper(["analyze", "--model-dir", setup.notesModelURL.path, "--input", input.path, "--output", output.path], workingDirectory: workspace, timeout: 7200)
        try Task.checkCancellation()
        guard try LocalAudioIdentity.read(request.audioURL) == identity else { throw LocalDocumentError.sourceChanged }
        let size = try output.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= 2_097_152 else { throw LocalDocumentError.invalidNotes }
        var notes = try JSONDecoder().decode(LocalStructuredNotes.self, from: Data(contentsOf: output))
        notes.preset = request.preset; notes.source = identity
        try request.validatePaths()
        try Task.checkCancellation()
        try store.saveNotes(notes, segments: transcript.segments)
    }
}
