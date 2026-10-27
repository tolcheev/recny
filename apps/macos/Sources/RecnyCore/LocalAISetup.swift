import Foundation

public enum LocalAISetupError: Error, LocalizedError, Sendable {
    case runtimeMissing, notesModelMissing, transcriptionSetupMissing, helperMissing
    public var errorDescription: String? {
        switch self {
        case .runtimeMissing: "Install the optional local notes runtime in Settings first."
        case .notesModelMissing: "Prepare the notes model in Settings before generating notes."
        case .transcriptionSetupMissing: "Prepare Parakeet and ffmpeg in Settings before transcribing."
        case .helperMissing: "The bundled local notes helper is missing. Reinstall Recny."
        }
    }
}
public struct LocalAIStatus: Decodable, Sendable {
    public let ready: Bool
    public let message: String
    public init(ready: Bool, message: String) { self.ready = ready; self.message = message }
}
public struct LocalAISetup: Sendable {
    public let environment: [String: String]
    public let baseURL: URL
    public var pythonURL: URL { baseURL.appendingPathComponent("runtime/bin/python3") }
    public var notesModelURL: URL { baseURL.appendingPathComponent("notes-model", isDirectory: true) }
    public init(environment: [String: String] = ProcessInfo.processInfo.environment, baseURL: URL? = nil) {
        self.environment = environment
        self.baseURL = baseURL ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/Recny/LocalAI", isDirectory: true)
    }
    public var helperURL: URL? {
        if Bundle.main.bundleURL.pathExtension == "app" {
            guard let resources = Bundle.main.resourceURL,
                  let bundle = Bundle(url: resources.appendingPathComponent("Recny_RecnyCore.bundle")) else { return nil }
            return bundle.url(forResource: "recny_local_notes", withExtension: "py")
        }
        return Bundle.module.url(forResource: "recny_local_notes", withExtension: "py")
    }
    public var runtimeInstalled: Bool { FileManager.default.isExecutableFile(atPath: pythonURL.path) }
    public var installCommand: String {
        let path = baseURL.appendingPathComponent("runtime").path.replacingOccurrences(of: "'", with: "'\\''")
        return "uv venv --python 3.11 '\(path)' && uv pip install --python '\(path)/bin/python3' 'mlx-lm==0.32.2' 'lm-format-enforcer==0.11.3'"
    }
    public func notesStatus() async -> LocalAIStatus {
        guard runtimeInstalled else { return .init(ready: false, message: "Install the optional local notes runtime first.") }
        do {
            let output = try await runHelper(["status", "--model-dir", notesModelURL.path], offline: true, timeout: 30)
            let status = try JSONDecoder().decode(LocalAIStatus.self, from: output)
            return .init(ready: status.ready, message: status.ready ? "Local notes model ready" : "Notes model or dependencies are incomplete. Prepare the model in Settings.")
        } catch { return .init(ready: false, message: "Could not verify local notes setup. Reinstall dependencies or prepare the model.") }
    }
    public func prepareNotesModel() async throws {
        _ = try await runHelper(["prepare", "--model-dir", notesModelURL.path], offline: false, timeout: 7200)
        let status = await notesStatus()
        try Task.checkCancellation()
        guard status.ready else { throw LocalAISetupError.notesModelMissing }
    }
    public func runHelper(_ arguments: [String], offline: Bool = true, workingDirectory: URL? = nil, timeout: TimeInterval = 3600) async throws -> Data {
        guard runtimeInstalled else { throw LocalAISetupError.runtimeMissing }
        guard let helperURL else { throw LocalAISetupError.helperMissing }
        return try await LocalToolProcess.run(executable: pythonURL, arguments: [helperURL.path] + arguments, environment: processEnvironment(offline: offline), workingDirectory: workingDirectory, timeout: timeout)
    }
    public func processEnvironment(offline: Bool = true) -> [String: String] {
        var result = environment
        result["PATH"] = LocalTranscriptionSetupInspector.executableSearchPaths(environment: environment).joined(separator: ":")
        result["HF_HUB_DISABLE_TELEMETRY"] = "1"
        result["DO_NOT_TRACK"] = "1"
        result["PYTHONDONTWRITEBYTECODE"] = "1"
        if offline { result["HF_HUB_OFFLINE"] = "1"; result["TRANSFORMERS_OFFLINE"] = "1" }
        else { result.removeValue(forKey: "HF_HUB_OFFLINE"); result.removeValue(forKey: "TRANSFORMERS_OFFLINE") }
        return result
    }
    public func parakeetModelURL() throws -> URL {
        guard LocalTranscriptionSetupInspector.status(environment: environment).canTranscribeWithoutSetup else { throw LocalAISetupError.transcriptionSetupMissing }
        let repository = LocalTranscriptionSetupInspector.huggingFaceCacheURL(environment: environment).appendingPathComponent("hub/models--mlx-community--parakeet-tdt-0.6b-v3")
        let snapshots = repository.appendingPathComponent("snapshots", isDirectory: true)
        var candidates: [URL] = []
        if let ref = try? String(contentsOf: repository.appendingPathComponent("refs/main"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines), ref.count == 40, ref.allSatisfy(\.isHexDigit) {
            candidates.append(snapshots.appendingPathComponent(ref))
        }
        candidates += (try? FileManager.default.contentsOfDirectory(at: snapshots, includingPropertiesForKeys: nil).sorted { $0.lastPathComponent < $1.lastPathComponent }) ?? []
        for candidate in candidates {
            if let size = try? candidate.appendingPathComponent("model.safetensors").resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 0,
               FileManager.default.fileExists(atPath: candidate.appendingPathComponent("config.json").path) { return candidate }
        }
        throw LocalAISetupError.transcriptionSetupMissing
    }
}
