import Combine
import Foundation

public enum LocalProcessingStage: String, Codable, Sendable {
    case queued, transcribing, analyzing, completed, failed, cancelled, interrupted
    public var isActive: Bool { [.queued, .transcribing, .analyzing].contains(self) }
    public var title: String {
        switch self {
        case .queued: "Queued"; case .transcribing: "Transcribing locally…"; case .analyzing: "Creating local notes…"
        case .completed: "Completed"; case .failed: "Failed"; case .cancelled: "Cancelled"; case .interrupted: "Interrupted — retry when ready"
        }
    }
}
public enum LocalProcessingMode: String, Codable, Sendable { case all, transcript, notes }
public struct LocalProcessingRequest: Sendable {
    public let recordingID: String
    public let sessionFolderURL: URL
    public let audioURL: URL
    public let storageRootURL: URL
    public let preset: LocalNotesPreset
    public let mode: LocalProcessingMode
    public init(recordingID: String, sessionFolderURL: URL, audioURL: URL, storageRootURL: URL, preset: LocalNotesPreset, mode: LocalProcessingMode) {
        self.recordingID = recordingID; self.sessionFolderURL = sessionFolderURL; self.audioURL = audioURL
        self.storageRootURL = storageRootURL; self.preset = preset; self.mode = mode
    }
    public func validatePaths() throws {
        let root = storageRootURL.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        let folder = sessionFolderURL.resolvingSymlinksInPath().standardizedFileURL.path
        guard folder.hasPrefix(root), audioURL.resolvingSymlinksInPath().standardizedFileURL.path.hasPrefix(folder + "/") else { throw LocalDocumentError.unsafePath }
        _ = try LocalRecordingDocumentStore(sessionFolderURL: sessionFolderURL).checkedURL("processing.json")
    }
}
public struct LocalProcessingJobState: Codable, Equatable, Sendable {
    public var recordingID: String
    public var stage: LocalProcessingStage
    public var preset: LocalNotesPreset
    public var mode: LocalProcessingMode
    public var message: String?
    public init(recordingID: String, stage: LocalProcessingStage, preset: LocalNotesPreset, mode: LocalProcessingMode, message: String? = nil) {
        self.recordingID = recordingID; self.stage = stage; self.preset = preset; self.mode = mode; self.message = message
    }
}
public protocol LocalRecordingProcessing: Sendable {
    func process(_ request: LocalProcessingRequest, progress: @escaping @Sendable (LocalProcessingStage) async throws -> Void) async throws
}

@MainActor
public final class LocalProcessingCoordinator: ObservableObject {
    public static let shared = LocalProcessingCoordinator(processor: LocalRecordingProcessor())
    @Published public private(set) var jobs: [String: LocalProcessingJobState] = [:]
    public var isBusy: Bool { activeID != nil || !queue.isEmpty }
    private let processor: any LocalRecordingProcessing
    private var queue: [LocalProcessingRequest] = []
    private var activeTask: Task<Void, Never>?
    private var activeID: String?
    public init(processor: any LocalRecordingProcessing) { self.processor = processor }
    public func isProcessing(_ id: String) -> Bool { jobs[id]?.stage.isActive == true || activeID == id }

    @discardableResult public func enqueue(_ request: LocalProcessingRequest) throws -> Bool {
        guard !isProcessing(request.recordingID) else { return false }
        try request.validatePaths()
        try update(request, stage: .queued)
        queue.append(request)
        startNext()
        return true
    }
    public func cancel(_ recordingID: String) {
        if activeID == recordingID { activeTask?.cancel(); return }
        if let index = queue.firstIndex(where: { $0.recordingID == recordingID }) {
            let request = queue.remove(at: index)
            finish(request, stage: .cancelled)
        }
    }
    public func restore(recordingID: String, sessionFolderURL: URL) throws {
        guard jobs[recordingID] == nil else { return }
        let store = LocalRecordingDocumentStore(sessionFolderURL: sessionFolderURL)
        guard let data = try store.read("processing.json") else { return }
        var state = try JSONDecoder().decode(LocalProcessingJobState.self, from: data)
        guard state.recordingID == recordingID else { throw LocalDocumentError.invalidTranscript }
        if state.stage.isActive {
            state.stage = .interrupted
            try store.write(state, name: "processing.json")
            // Only this feature's uniquely named temporary directories are disposable.
            let children = try FileManager.default.contentsOfDirectory(at: store.directory, includingPropertiesForKeys: nil)
            for child in children where child.lastPathComponent.hasPrefix("work-") && UUID(uuidString: String(child.lastPathComponent.dropFirst(5))) != nil {
                let safe = try store.checkedURL(child.lastPathComponent)
                try FileManager.default.removeItem(at: safe)
            }
        }
        jobs[recordingID] = state
    }
    private func update(_ request: LocalProcessingRequest, stage: LocalProcessingStage, message: String? = nil) throws {
        let state = LocalProcessingJobState(recordingID: request.recordingID, stage: stage, preset: request.preset, mode: request.mode, message: message)
        try LocalRecordingDocumentStore(sessionFolderURL: request.sessionFolderURL).write(state, name: "processing.json")
        jobs[request.recordingID] = state
        AppLogger.file(.info, category: "local-ai", "stage=\(stage.rawValue) recording_id=\(request.recordingID)")
    }
    private func finish(_ request: LocalProcessingRequest, stage: LocalProcessingStage, message: String? = nil) {
        do { try update(request, stage: stage, message: message) }
        catch {
            jobs[request.recordingID] = .init(recordingID: request.recordingID, stage: .failed, preset: request.preset, mode: request.mode, message: "Could not save processing state. Check local storage.")
            AppLogger.file(.error, category: "local-ai", "state_save_failed recording_id=\(request.recordingID)")
        }
    }
    private func startNext() {
        guard activeTask == nil, !queue.isEmpty else { return }
        let request = queue.removeFirst(); activeID = request.recordingID
        activeTask = Task { [self] in
            do {
                try await processor.process(request) { [weak self] stage in
                    try Task.checkCancellation()
                    try await self?.update(request, stage: stage)
                }
                try Task.checkCancellation()
                finish(request, stage: .completed)
            } catch is CancellationError {
                finish(request, stage: .cancelled)
            } catch {
                let message: String
                if let known = error as? LocalDocumentError { message = known.localizedDescription }
                else if let known = error as? LocalToolError { message = known.localizedDescription }
                else if let known = error as? LocalAISetupError { message = known.localizedDescription }
                else { message = "Local processing failed. Check available storage and model setup, then retry." }
                finish(request, stage: .failed, message: message)
            }
            activeID = nil; activeTask = nil; startNext()
        }
    }
}
