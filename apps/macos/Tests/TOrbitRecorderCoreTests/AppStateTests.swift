import Foundation
import Testing
@testable import TOrbitRecorderCore

@MainActor
struct AppStateTests {
    @Test
    func startsAndStopsWithStubController() async throws {
        let controller = StubRecordingController()
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder()
        )

        try await appState.startRecording()

        #expect(appState.status == .recording)
        #expect(appState.micStatus == .ready)
        #expect(appState.systemAudioStatus == .ready)
        #expect(appState.currentRecordingDuration >= 0)

        try await appState.stopRecording()

        #expect(appState.status == .idle)
        #expect(appState.micStatus == .idle)
        #expect(appState.systemAudioStatus == .idle)
    }

    @Test
    func refusesDuplicateStart() async throws {
        let controller = StubRecordingController()
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder()
        )

        try await appState.startRecording()

        await #expect(throws: RecordingControllerError.alreadyRecording) {
            try await appState.startRecording()
        }
    }

    private static func testOutputFolder() -> URL {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()

        return packageRoot
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("test-recordings", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
