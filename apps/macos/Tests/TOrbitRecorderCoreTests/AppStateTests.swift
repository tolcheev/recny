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
    func stopRecordingShowsStoppingStateAndIgnoresDuplicateStop() async throws {
        let controller = DelayedStopRecordingController(stopDelay: .milliseconds(150))
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()

        let firstStop = Task {
            try await appState.stopRecording()
        }

        try await Task.sleep(for: .milliseconds(20))

        #expect(appState.isStoppingRecording)

        try await appState.stopRecording()
        #expect(controller.stopCallCount == 1)

        try await firstStop.value

        #expect(appState.isStoppingRecording == false)
        #expect(appState.status == .idle)
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
    func autoStartUsesRunningZoomAsRecordingSourceWhenUserSwitchedWindows() async throws {
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
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoom],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        try await appState.stopRecording()
        let draft = try #require(appState.postCallDraft)
        let metadata = try FileSystemRecordingStore(rootURL: outputFolder).readMetadata(at: draft.metadataURL)
        #expect(metadata.source.appName == "zoom.us")
        #expect(metadata.source.bundleID == "us.zoom.xos")
        #expect(metadata.source.trigger == "autostart")
        #expect(metadata.source.ruleID == "autostart.v2.zoom")
        #expect(metadata.source.reason == "Zoom call detected with microphone and system audio activity.")
    }

    @Test
    func autoStartPublishesStartedNotificationForBrowserCall() async {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Google Chrome"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "QA mentorship - Google Meet"
        )
        let audio = AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: audio,
            now: startedAt
        )

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: audio,
            now: startedAt.addingTimeInterval(15)
        )

        #expect(appState.status == .recording)
        #expect(appState.autoStartNotificationMessage == "Recording started: browser call detected")
    }

    @Test
    func autoStartedZoomRecordingStopsAfterCallSignalIsLost() async throws {
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
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: zoom,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: nil,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: nil,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: startedAt.addingTimeInterval(55)
        )

        #expect(appState.status == .idle)
        #expect(appState.autoStartNotificationMessage == "Recording stopped: call ended")
        #expect(appState.postCallDraft != nil)
    }

    @Test
    func autoStartedZoomRecordingStopsWhenZoomReturnsToHomeWindowEvenIfRecorderAudioIsActive() async throws {
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
        let zoomMeeting = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting"
        )
        let zoomHome = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "zoom Workplace"
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: zoomMeeting,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomHome],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomHome],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(55)
        )

        #expect(appState.status == .idle)
        #expect(appState.autoStartNotificationMessage == "Recording stopped: call ended")
    }

    @Test
    func autoStartedZoomRecordingKeepsRunningWhileMeetingWindowExists() async throws {
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
        let zoomMeeting = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting"
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: zoomMeeting,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomMeeting],
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: startedAt.addingTimeInterval(55)
        )

        #expect(appState.status == .recording)
        try await appState.stopRecording()
    }

    @Test
    func manualRecordingDoesNotAutoStopWhenAudioActivityIsSilent() async throws {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()

        await appState.evaluateAutoStart(
            activeApplication: nil,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: Date(timeIntervalSince1970: 1_716_468_000)
        )

        await appState.evaluateAutoStart(
            activeApplication: nil,
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: Date(timeIntervalSince1970: 1_716_468_100)
        )

        #expect(appState.status == .recording)
        try await appState.stopRecording()
    }

    @Test
    func launchAtLoginPreferenceUpdatesSettingsStateAndDiagnosticsError() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        appState.setLaunchAtLoginPreference(true, errorMessage: "Could not update Launch at Login.")

        #expect(appState.privacySettings.launchAtLogin)
        #expect(appState.launchAtLoginLastErrorMessage == "Could not update Launch at Login.")

        appState.setLaunchAtLoginPreference(false)

        #expect(appState.privacySettings.launchAtLogin == false)
        #expect(appState.launchAtLoginLastErrorMessage == nil)
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
    func normalStopDoesNotOpenTagDialogAutomatically() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: NeedsTaggingRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()
        try await appState.stopRecording()

        let draft = try #require(appState.postCallDraft)
        #expect(draft.status == .needsTagging)
        #expect(!appState.isPostCallPanelPresented)
    }

    @Test
    func staleSystemAudioProbeFlagDoesNotGrantCurrentBuild() {
        let legacyKey = "com.torbit.recorder.systemAudioPermissionProbeSucceeded"
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        UserDefaults.standard.set(true, forKey: legacyKey)
        defer {
            UserDefaults.standard.removeObject(forKey: legacyKey)
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker(
                snapshot: RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .notDetermined,
                    storage: .granted
                )
            )
        )

        #expect(appState.permissionSnapshot.screenSystemAudio == .notDetermined)
        #expect(!appState.isRecordingStartAllowed)
    }

    @Test
    func recordingMarkersPersistAfterStop() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted
        )

        try await appState.startRecording()
        appState.addMarker(.important)
        appState.addMarker(.badAudio)

        #expect(appState.activeMarkers.map(\.label) == ["Important", "Bad audio"])

        try await appState.stopRecording()
        let draft = try #require(appState.postCallDraft)
        let metadata = try FileSystemRecordingStore(rootURL: outputFolder)
            .readMetadata(at: draft.metadataURL)

        #expect(metadata.markers.map(\.label) == ["Important", "Bad audio"])
        #expect(metadata.markers.map(\.tags) == [["important"], ["bad_audio"]])
        #expect(appState.activeMarkers.isEmpty)
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
    func successfulSystemAudioProbeOverridesStaticNotDeterminedSnapshot() {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker(
                snapshot: RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .notDetermined,
                    storage: .granted
                )
            )
        )

        appState.noteSystemAudioPermissionRequestSucceeded()
        appState.refreshPermissionSnapshot()

        #expect(appState.permissionSnapshot.screenSystemAudio == .granted)
        #expect(!appState.shouldShowPermissionsOnboarding)
        #expect(appState.isRecordingStartAllowed)
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
    func preflightBlocksStartWhenFreeDiskSpaceIsBelowMinimum() async {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: {
                [MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")]
            },
            preflightChecker: DefaultRecordingPreflightChecker(minimumFreeDiskSpaceBytes: .max)
        )

        await #expect(throws: RecordingControllerError.preflightFailed("At least 2 GB of free disk space is required before recording.")) {
            try await appState.startRecording()
        }

        #expect(appState.status == .error)
        #expect(appState.errorMessage?.contains("At least 2 GB") == true)
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

    private static var currentSystemAudioProbeKey: String {
        let fingerprint = "\(BuildInfo.appVersion).\(BuildInfo.gitCommit)"
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "com.torbit.recorder.systemAudioPermissionProbeSucceeded.\(fingerprint)"
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

private final class DelayedStopRecordingController: RecordingController {
    private let wrapped = StubRecordingController()
    private let stopDelay: Duration
    private(set) var stopCallCount = 0

    init(stopDelay: Duration) {
        self.stopDelay = stopDelay
    }

    func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate {
        try await wrapped.startRecording(
            outputFolder: outputFolder,
            source: source,
            settings: settings
        )
    }

    func stopRecording() async throws -> RecordingControllerUpdate {
        stopCallCount += 1
        try await Task.sleep(for: stopDelay)
        return try await wrapped.stopRecording()
    }
}

private final class NeedsTaggingRecordingController: RecordingController {
    private var session: RecordingSession?
    private var store: FileSystemRecordingStore?
    private var startedAt: Date?

    func startRecording(
        outputFolder: URL,
        source: RecordingSource,
        settings: RecordingRuntimeSettings
    ) async throws -> RecordingControllerUpdate {
        let startedAt = Date()
        let store = FileSystemRecordingStore(rootURL: outputFolder)
        let session = try store.startSession(startedAt: startedAt, source: source)

        self.startedAt = startedAt
        self.session = session
        self.store = store

        return RecordingControllerUpdate(
            status: .recording,
            micStatus: .ready,
            systemAudioStatus: .ready,
            startedAt: startedAt,
            duration: 0,
            session: session
        )
    }

    func stopRecording() async throws -> RecordingControllerUpdate {
        guard let session, let store, let startedAt else {
            throw RecordingControllerError.notRecording
        }

        let duration: TimeInterval = 90
        let draft = try store.stopSession(
            session,
            endedAt: startedAt.addingTimeInterval(duration),
            duration: duration,
            status: .needsTagging,
            shortRecordingThresholdSeconds: TaggingStatus.shortRecordingThresholdSeconds
        )

        self.session = nil
        self.store = nil
        self.startedAt = nil

        return RecordingControllerUpdate(
            status: .idle,
            micStatus: .idle,
            systemAudioStatus: .idle,
            duration: duration,
            postCallDraft: draft
        )
    }
}
