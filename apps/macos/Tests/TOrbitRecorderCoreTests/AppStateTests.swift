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
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
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
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()

        await #expect(throws: RecordingControllerError.alreadyRecording) {
            try await appState.startRecording()
        }
    }

    @Test
    func systemAudioPermissionErrorUpdatesSystemStatus() async {
        let appState = AppState(
            recordingController: FailingRecordingController(
                error: RecordingControllerError.systemAudioPermissionDenied("denied")
            ),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        await #expect(throws: RecordingControllerError.systemAudioPermissionDenied("denied")) {
            try await appState.startRecording()
        }

        #expect(appState.status == .error)
        #expect(appState.micStatus == .idle)
        #expect(appState.systemAudioStatus == .permissionDenied)
    }

    @Test
    func stopCreatesShortRecordingMetadataForShortSession() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()
        try await appState.stopRecording()

        let draft = try #require(appState.postCallDraft)
        #expect(draft.status == .shortRecording)
        #expect(!appState.isPostCallPanelPresented)

        let metadataURL = draft.metadataURL
        #expect(FileManager.default.fileExists(atPath: metadataURL.path(percentEncoded: false)))

        let store = FileSystemRecordingStore(rootURL: outputFolder)
        let recordings = try store.recordings(filters: RecordingListFilters(status: .shortRecording))
        #expect(recordings.map(\.id).contains(draft.id))
        #expect(recordings.first(where: { $0.id == draft.id })?.status == .shortRecording)
    }

    @Test
    func autoStartStartsAfterDetectionDuration() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Zoom"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let activeApp = ActiveApplicationSnapshot(name: "Zoom", bundleID: "us.zoom.xos")
        let audio = AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: audio,
            now: startedAt
        )
        #expect(appState.status == .idle)

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: audio,
            now: startedAt.addingTimeInterval(15)
        )
        #expect(appState.status == .recording)

        try await appState.stopRecording()
        let draft = try #require(appState.postCallDraft)
        let metadata = try FileSystemRecordingStore(rootURL: outputFolder).readMetadata(at: draft.metadataURL)
        #expect(metadata.source.appName == "Zoom")
        #expect(metadata.source.bundleID == "us.zoom.xos")
        #expect(metadata.source.trigger == "autostart")
        #expect(metadata.source.ruleID == "autostart.v2.zoom")
        #expect(metadata.source.confidence == "high")
        #expect(metadata.source.reason == "Zoom active with microphone activity.")
    }

    @Test
    func savePostCallTagsToMetadataAndSQLite() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()
        try await appState.stopRecording()

        var draft = try #require(appState.postCallDraft)
        draft.title = "Lead call follow-up"
        draft.category = "lead"
        draft.participant = "Ivan Lead"
        draft.tags = ["#лид", "#продажа"]
        draft.status = .saved

        try appState.savePostCallDraft(draft)

        let metadata = try FileSystemRecordingStore(rootURL: outputFolder)
            .readMetadata(at: draft.metadataURL)
        #expect(metadata.title == "Lead call follow-up")
        #expect(metadata.category == "lead")
        #expect(metadata.participants == ["Ivan Lead"])
        #expect(metadata.tags == ["#лид", "#продажа"])
        #expect(metadata.status == .saved)

        let filtered = try FileSystemRecordingStore(rootURL: outputFolder)
            .recordings(filterTag: "#лид")
        #expect(filtered.map(\.id).contains(draft.id))
    }

    @Test
    func preflightBlocksStartWhenPermissionsAreMissing() async {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker(
                snapshot: RecorderPermissionSnapshot(
                    microphone: .missing,
                    screenSystemAudio: .granted,
                    storage: .granted
                )
            )
        )

        await #expect(throws: RecordingControllerError.preflightFailed("Microphone access is required before recording.")) {
            try await appState.startRecording()
        }

        #expect(appState.status == .error)
        #expect(appState.shouldShowPermissionsOnboarding)
        let unsortedURL = outputFolder.appendingPathComponent("Inbox/Unsorted", isDirectory: true)
        let sessionFolders = (try? FileManager.default.contentsOfDirectory(
            at: unsortedURL,
            includingPropertiesForKeys: nil
        )) ?? []
        #expect(sessionFolders.isEmpty)
        #expect(
            (try? FileSystemRecordingStore(rootURL: outputFolder).recoverableSessions().isEmpty) == true
        )
    }

    @Test
    func preflightBlocksStartWhenStorageIsNotWritable() async {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker(
                snapshot: RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .granted,
                    storage: .denied
                )
            )
        )

        await #expect(throws: RecordingControllerError.preflightFailed("The recordings folder must be writable before recording.")) {
            try await appState.startRecording()
        }

        #expect(appState.status == .error)
        #expect(appState.recordingStartBlockingReason == "The recordings folder must be writable before recording.")
    }

    @Test
    func autoMicrophoneRefreshUpdatesNextRecordingButNotActiveRecording() async throws {
        var devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
        ]
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: { devices }
        )

        #expect(appState.selectedMicrophoneName == "MacBook Pro Microphone")
        #expect(appState.recommendedMicrophoneName == "MacBook Pro Microphone")
        #expect(appState.microphoneSelectionReason == "AirPods microphone avoided because built-in microphone is available.")

        try await appState.startRecording()

        devices = [
            MicrophoneInputDevice(id: "airpods", name: "AirPods Pro"),
            MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone"),
            MicrophoneInputDevice(id: "shure", name: "Shure MV7")
        ]
        appState.refreshMicrophoneDevices()

        #expect(appState.selectedMicrophoneName == "MacBook Pro Microphone")
        #expect(appState.recommendedMicrophoneName == "Shure MV7")

        try await appState.stopRecording()
        appState.refreshMicrophoneDevices()

        #expect(appState.selectedMicrophoneName == "Shure MV7")
        #expect(appState.microphoneSelectionReason == "AirPods microphone avoided because external microphone is available.")
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

private final class StaticPermissionChecker: RecordingPermissionChecking, @unchecked Sendable {
    static let allGranted = StaticPermissionChecker(
        snapshot: RecorderPermissionSnapshot(
            microphone: .granted,
            screenSystemAudio: .granted,
            storage: .granted
        )
    )

    private let snapshot: RecorderPermissionSnapshot

    init(snapshot: RecorderPermissionSnapshot) {
        self.snapshot = snapshot
    }

    func snapshot(
        outputFolderURL: URL,
        screenSystemAudioSettingsOpened: Bool,
        lastErrorMessage: String?
    ) -> RecorderPermissionSnapshot {
        snapshot
    }
}

private final class FailingRecordingController: RecordingController {
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate {
        throw error
    }

    func stopRecording() async throws -> RecordingControllerUpdate {
        throw error
    }
}
