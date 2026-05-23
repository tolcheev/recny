import Combine
import Foundation

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var status: RecordingStatus
    @Published public private(set) var currentRecordingDuration: TimeInterval
    @Published public private(set) var micStatus: CaptureStatus
    @Published public private(set) var systemAudioStatus: CaptureStatus
    @Published public private(set) var errorMessage: String?

    public let outputFolderURL: URL

    private let recordingController: RecordingController
    private var recordingStartedAt: Date?
    private var durationTask: Task<Void, Never>?

    public var outputFolderPath: String {
        outputFolderURL.path(percentEncoded: false)
    }

    public var formattedDuration: String {
        Self.formatDuration(currentRecordingDuration)
    }

    public init(
        recordingController: RecordingController = StubRecordingController(),
        outputFolderURL: URL = RecordingPaths.defaultRoot
    ) {
        self.recordingController = recordingController
        self.outputFolderURL = outputFolderURL
        self.status = .idle
        self.currentRecordingDuration = 0
        self.micStatus = .idle
        self.systemAudioStatus = .idle
        self.errorMessage = nil
    }

    deinit {
        durationTask?.cancel()
    }

    public func startRecording() async throws {
        do {
            try FileManager.default.createDirectory(
                at: outputFolderURL,
                withIntermediateDirectories: true
            )

            let update = try await recordingController.startRecording(outputFolder: outputFolderURL)
            apply(update)
            recordingStartedAt = update.startedAt ?? Date()
            currentRecordingDuration = 0
            errorMessage = nil
            startDurationClock()
            AppLogger.recording.info("Recording state changed to recording")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to start recording: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    public func stopRecording() async throws {
        do {
            let update = try await recordingController.stopRecording()
            apply(update)
            stopDurationClock()
            errorMessage = nil
            AppLogger.recording.info("Recording state changed to idle")
        } catch {
            applyError(error)
            AppLogger.recording.error("Failed to stop recording: \(String(describing: error), privacy: .public)")
            throw error
        }
    }

    private func apply(_ update: RecordingControllerUpdate) {
        status = update.status
        micStatus = update.micStatus
        systemAudioStatus = update.systemAudioStatus

        if let duration = update.duration {
            currentRecordingDuration = duration
        }
    }

    private func applyError(_ error: Error) {
        status = .error
        micStatus = .error
        systemAudioStatus = .error
        errorMessage = String(describing: error)
        stopDurationClock()
    }

    private func startDurationClock() {
        durationTask?.cancel()

        durationTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else {
                    return
                }

                self.refreshDuration()

                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }
            }
        }
    }

    private func stopDurationClock() {
        durationTask?.cancel()
        durationTask = nil
        recordingStartedAt = nil
        currentRecordingDuration = 0
    }

    private func refreshDuration() {
        guard status == .recording, let recordingStartedAt else {
            return
        }

        currentRecordingDuration = Date().timeIntervalSince(recordingStartedAt)
    }

    private static func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }
}
