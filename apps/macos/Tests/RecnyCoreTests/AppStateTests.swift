import Foundation
import Testing
@testable import RecnyCore

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
    func exposesCurrentSessionFolderForScreenshotsWhileRecording() async throws {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        #expect(appState.currentSessionFolderURL == nil)
        #expect(appState.preferredScreenshotFolderURL == nil)

        try await appState.startRecording()

        let activeFolder = try #require(appState.currentSessionFolderURL)
        #expect(appState.preferredScreenshotFolderURL == activeFolder)

        try await appState.stopRecording()

        #expect(appState.currentSessionFolderURL == nil)
        #expect(appState.preferredScreenshotFolderURL == appState.lastRecording?.sessionFolderURL)
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
    func durationFreezesWhileStopFinalizesFiles() async throws {
        let controller = DelayedStopRecordingController(stopDelay: .seconds(1))
        let appState = AppState(
            recordingController: controller,
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )
        try await appState.startRecording()
        let stop = Task { try await appState.stopRecording() }
        while !appState.isStoppingRecording { await Task.yield() }
        let durationAtStop = appState.currentRecordingDuration
        try await Task.sleep(for: .milliseconds(550))
        #expect(appState.currentRecordingDuration == durationAtStop)
        try await stop.value
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
    func stoppedZoomRecordingDoesNotImmediatelyAutoStartAgainDuringCooldown() async throws {
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
        let zoomProcessAudio = AudioActivitySnapshot(
            microphoneActive: false,
            systemAudioActive: false,
            processActivities: [
                AudioProcessActivitySnapshot(
                    processID: 44,
                    bundleID: "us.zoom.xos",
                    isRunningInput: false,
                    isRunningOutput: true
                )
            ]
        )

        await appState.evaluateAutoStart(
            activeApplication: zoom,
            audioActivity: zoomProcessAudio,
            now: Date()
        )
        #expect(appState.status == .recording)

        try await appState.stopRecording()
        #expect(appState.status == .idle)

        await appState.evaluateAutoStart(
            activeApplication: zoom,
            audioActivity: zoomProcessAudio,
            now: Date().addingTimeInterval(2)
        )
        #expect(appState.status == .idle)
    }

    @Test
    func askFirstAutoStartWaitsForExplicitConfirmation() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                mode: .askFirst,
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

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: audio,
            now: startedAt.addingTimeInterval(15)
        )

        #expect(appState.status == .idle)
        let prompt = try #require(appState.pendingAutoStartPrompt)
        #expect(prompt.source.appName == "Zoom")
        #expect(prompt.source.ruleID == "autostart.v2.zoom")
        try await appState.confirmPendingAutoStart()

        #expect(appState.pendingAutoStartPrompt == nil)
        #expect(appState.status == .recording)

        try await appState.stopRecording()
        let draft = try #require(appState.postCallDraft)
        let metadata = try FileSystemRecordingStore(rootURL: outputFolder).readMetadata(at: draft.metadataURL)
        #expect(metadata.source.appName == "Zoom")
        #expect(metadata.source.trigger == "autostart")
    }

    @Test
    func ignorePendingAutoStartClearsPromptWithoutRecording() async throws {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                mode: .askFirst,
                whitelist: ["Zoom"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let activeApp = ActiveApplicationSnapshot(name: "Zoom", bundleID: "us.zoom.xos")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt
        )
        await appState.evaluateAutoStart(
            activeApplication: activeApp,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt.addingTimeInterval(15)
        )

        #expect(appState.pendingAutoStartPrompt != nil)

        appState.ignorePendingAutoStart()

        #expect(appState.pendingAutoStartPrompt == nil)
        #expect(appState.status == .idle)
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
        #expect(metadata.source.appName == "Zoom")
        #expect(metadata.source.bundleID == "us.zoom.xos")
        #expect(metadata.source.trigger == "autostart")
        #expect(metadata.source.ruleID == "autostart.v2.zoom")
        #expect(metadata.source.reason == "Zoom call detected with microphone and system audio activity.")
    }

    @Test
    func autoStartUsesZoomMeetingSourceWhenUserSwitchedWindowsBeforeSystemAudioSpeaks() async throws {
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
        let zoom = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoom],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt
        )
        #expect(appState.status == .recording)

        try await appState.stopRecording()
        let draft = try #require(appState.postCallDraft)
        let metadata = try FileSystemRecordingStore(rootURL: outputFolder).readMetadata(at: draft.metadataURL)
        #expect(metadata.source.appName == "Zoom")
        #expect(metadata.source.bundleID == "us.zoom.xos")
        #expect(metadata.source.trigger == "autostart")
        #expect(metadata.source.ruleID == "autostart.v2.zoom")
        #expect(metadata.source.reason == "Zoom meeting window detected with microphone activity.")
    }

    @Test
    func autoStartStartsBrowserCallWithoutUserNotificationState() async {
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
    }

    @Test
    func autoStartedZoomRecordingStopsWhenZoomHasNoMeetingWindowAndOnlyRecorderMicIsActive() async throws {
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
        let zoomIdle = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: nil
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
            runningApplications: [zoomIdle],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomIdle],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt.addingTimeInterval(55)
        )

        #expect(appState.status == .idle)
    }

    @Test
    func autoStopDelayDefaultsToTenSecondsAndShortensGracePeriod() async throws {
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
        #expect(appState.autoStartSettings.autoStopDelaySeconds == 10)

        let zoomMeeting = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting"
        )
        let zoomIdle = ActiveApplicationSnapshot(
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

        // Signal lost at t=20, grace = 10s, so at t=25 we are within grace.
        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomIdle],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomIdle],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(25)
        )
        #expect(appState.status == .recording)

        // After 11s post signal-lost (>10s grace), must stop.
        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomIdle],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(31)
        )
        #expect(appState.status == .idle)
    }

    @Test
    func autoStartMonitoringPollsOftenEnoughForTenSecondAutoStop() {
        #expect(AppState.defaultAutoStartMonitoringPollIntervalSeconds == 1)
        #expect(AppState.defaultAutoStartMonitoringPollIntervalSeconds < AutoStartSettings.defaultAutoStopDelaySeconds)
    }

    @Test
    func setAutoStopDelaySnapsToNearestAllowedValue() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )

        appState.setAutoStopDelaySeconds(30)
        #expect(appState.autoStartSettings.autoStopDelaySeconds == 30)

        appState.setAutoStopDelaySeconds(60)
        #expect(appState.autoStartSettings.autoStopDelaySeconds == 60)

        // Out-of-range values must snap to the closest allowed entry.
        appState.setAutoStopDelaySeconds(45)
        #expect([30.0, 60.0].contains(appState.autoStartSettings.autoStopDelaySeconds))

        appState.setAutoStopDelaySeconds(0)
        #expect(appState.autoStartSettings.autoStopDelaySeconds == 10)
    }

    @Test
    func autoStartedZoomRecordingKeepsRunningWhenWindowTitlesAreNilAndSystemAudioIsActive() async throws {
        // Real-world scenario: macOS Sequoia user granted only the
        // System Audio Recording sub-permission so window titles are nil,
        // and the Core Audio process tap keeps both default input and
        // output devices in IsRunning=true. The user can switch to Safari,
        // IDE, notes, or slides during a real call; unavailable window
        // titles alone must not stop a Zoom recording while system audio
        // is still active.
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
        let zoomBlind = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: nil
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: zoomMeeting,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomBlind],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomBlind],
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(55)
        )
        #expect(appState.status == .recording)
    }

    @Test
    func autoStartedZoomRecordingKeepsRunningWhenZoomProcessAudioIsActive() async throws {
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
        let zoomBlind = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: nil
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
            runningApplications: [zoomBlind],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: false,
                systemAudioActive: false,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 44,
                        bundleID: "us.zoom.ZoomDaemon",
                        isRunningInput: false,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(55)
        )

        #expect(appState.status == .recording)
        try await appState.stopRecording()
    }

    @Test
    func autoStartedZoomRecordingStopsWhenZoomProcessAudioStopsEvenIfGlobalAudioIsActive() async throws {
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
        let zoomBlind = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: nil
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
            runningApplications: [zoomBlind],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 44,
                        bundleID: "us.zoom.xos",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 55,
                        bundleID: "com.apple.Music",
                        isRunningInput: false,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(20)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [zoomBlind],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 44,
                        bundleID: "us.zoom.xos",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 55,
                        bundleID: "com.apple.Music",
                        isRunningInput: false,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(31)
        )

        #expect(appState.status == .idle)
    }

    @Test
    func autoStartedZoomRecordingKeepsRunningWhenZoomIsFrontmostEvenWithoutWindowTitle() async throws {
        // When window titles are unavailable but Zoom is frontmost, the
        // user is interacting with the call — must keep recording.
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
        let zoomFrontmostNoTitle = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: nil
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: zoomMeeting,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: zoomFrontmostNoTitle,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
            now: startedAt.addingTimeInterval(55)
        )
        #expect(appState.status == .recording)
        try await appState.stopRecording()
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
    func autoStartedTeamsRecordingKeepsRunningWhileMeetingWindowExists() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Microsoft Teams"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let teamsMeeting = ActiveApplicationSnapshot(
            name: "Microsoft Teams",
            bundleID: "com.microsoft.teams2",
            windowTitle: "Meeting with Vladislav Tolcheev"
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: teamsMeeting,
            audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [teamsMeeting],
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: startedAt.addingTimeInterval(55)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: codex,
            runningApplications: [teamsMeeting],
            audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
            now: startedAt.addingTimeInterval(66)
        )
        #expect(appState.status == .recording)
        try await appState.stopRecording()
    }

    @Test
    func autoStartedTelemostRecordingStopsWhenTelemostProcessAudioStopsEvenIfTelegramIsActive() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Yandex Telemost", "Telegram"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let telemost = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost"
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: telemost,
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(15)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            runningApplications: [telemost],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 701,
                        bundleID: "ru.keepcoder.Telegram",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(25)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            runningApplications: [telemost],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 701,
                        bundleID: "ru.keepcoder.Telegram",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(36)
        )
        #expect(appState.status == .idle)
    }

    @Test
    func autoStartedTelemostRecordingStopsDespiteStaleMeetingTitle() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Yandex Telemost", "Telegram"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15
            )
        )
        let telemost = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost",
            windowTitle: "Встреча"
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: telemost,
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(15)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            runningApplications: [telemost],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 701,
                        bundleID: "ru.keepcoder.Telegram",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(25)
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            runningApplications: [telemost],
            audioActivity: AudioActivitySnapshot(
                microphoneActive: true,
                systemAudioActive: true,
                processActivities: [
                    AudioProcessActivitySnapshot(
                        processID: 700,
                        bundleID: "ru.yandex.desktop.telemost",
                        isRunningInput: false,
                        isRunningOutput: false
                    ),
                    AudioProcessActivitySnapshot(
                        processID: 701,
                        bundleID: "ru.keepcoder.Telegram",
                        isRunningInput: true,
                        isRunningOutput: true
                    )
                ]
            ),
            now: startedAt.addingTimeInterval(36)
        )
        #expect(appState.status == .idle)
    }

    @Test
    func autoStartedTelemostRecordingStopsWhenTelemostSignalsAreUnavailableDespiteGlobalAudio() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Yandex Telemost"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15,
                autoStopDelaySeconds: 10
            )
        )
        try await appState.startRecording(
            source: RecordingSource(
                appName: "Yandex Telemost",
                bundleID: "ru.yandex.desktop.telemost",
                trigger: "autostart",
                ruleID: "autostart.v2.telemost_process_audio",
                confidence: "high",
                reason: "Yandex Telemost process is using audio."
            )
        )

        let telemostWithoutTitle = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost"
        )
        let browser = ActiveApplicationSnapshot(name: "Google Chrome", bundleID: "com.google.Chrome")
        let globalAudioOnly = AudioActivitySnapshot(
            microphoneActive: true,
            systemAudioActive: true,
            processActivities: [],
            processActivityAvailable: false
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: browser,
            runningApplications: [telemostWithoutTitle],
            audioActivity: globalAudioOnly,
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: browser,
            runningApplications: [telemostWithoutTitle],
            audioActivity: globalAudioOnly,
            now: startedAt.addingTimeInterval(11)
        )
        #expect(appState.status == .idle)
    }

    @Test
    func autoStartedTelegramRecordingStopsWhenOnlyTelegramPlaybackAndOtherMicRemainActive() async throws {
        let outputFolder = Self.testOutputFolder()
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: outputFolder,
            permissionChecker: StaticPermissionChecker.allGranted,
            autoStartSettings: AutoStartSettings(
                isEnabled: true,
                whitelist: ["Telegram"],
                blacklist: [],
                cooldownSeconds: 180,
                minDetectionDurationSeconds: 15,
                autoStopDelaySeconds: 10
            )
        )
        try await appState.startRecording(
            source: RecordingSource(
                appName: "Telegram",
                bundleID: "ru.keepcoder.Telegram",
                trigger: "autostart",
                ruleID: "autostart.v2.known_call_app",
                confidence: "high",
                reason: "Telegram process is using input and output audio."
            )
        )

        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let playbackOnly = AudioActivitySnapshot(
            microphoneActive: true,
            systemAudioActive: true,
            processActivities: [
                AudioProcessActivitySnapshot(
                    processID: 100,
                    bundleID: "ru.keepcoder.Telegram",
                    isRunningInput: false,
                    isRunningOutput: true
                ),
                AudioProcessActivitySnapshot(
                    processID: 200,
                    bundleID: "com.apple.QuickTimePlayerX",
                    isRunningInput: true,
                    isRunningOutput: false
                )
            ]
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            audioActivity: playbackOnly,
            now: startedAt
        )
        #expect(appState.status == .recording)

        await appState.evaluateAutoStart(
            activeApplication: telegram,
            audioActivity: playbackOnly,
            now: startedAt.addingTimeInterval(11)
        )

        #expect(appState.status == .idle)
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
    func systemAudioProbeCacheKeyIncludesBuildDateForLocalAdHocRebuilds() {
        let key = AppState.systemAudioPermissionProbeSucceededKeyForTesting
        #expect(key.contains(Self.sanitized(BuildInfo.buildDate)))
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
    func cachedSystemAudioProbeUnlocksStartOnCurrentBuildRelaunch() {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        let firstAppState = AppState(
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

        firstAppState.noteSystemAudioPermissionRequestSucceeded()
        #expect(firstAppState.permissionSnapshot.screenSystemAudio == .granted)
        #expect(firstAppState.isRecordingStartAllowed)

        let relaunchedAppState = AppState(
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

        #expect(relaunchedAppState.permissionSnapshot.screenSystemAudio == .granted)
        #expect(relaunchedAppState.isRecordingStartAllowed)
    }

    @Test
    func systemAudioPermissionRequestInProgressBlocksRecordingStartAndReady() {
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

        appState.noteSystemAudioPermissionRequestStarted()

        #expect(appState.isSystemAudioPermissionRequestInProgress)
        #expect(appState.permissionSnapshot.screenSystemAudio != .granted)
        #expect(!appState.isRecordingStartAllowed)
        #expect(appState.shouldShowPermissionsOnboarding)
        #expect(appState.shouldShowPermissionChecklist)
        #expect(
            appState.recordingStartBlockingReason
                == "Waiting for system audio permission. Click Allow on the macOS prompt."
        )
    }

    @Test
    func pendingSystemAudioProbeSuppressesCachedGrantPromotion() {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        // Simulate cached "probe succeeded" from a previous launch.
        let firstAppState = AppState(
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
        firstAppState.noteSystemAudioPermissionRequestSucceeded()
        #expect(firstAppState.permissionSnapshot.screenSystemAudio == .granted)

        // A new launch with cached UserDefaults flag must NOT immediately
        // show Ready while a fresh permission request is in flight.
        let relaunchedAppState = AppState(
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
        #expect(relaunchedAppState.permissionSnapshot.screenSystemAudio == .granted)
        #expect(relaunchedAppState.isRecordingStartAllowed)

        // Now start a new probe — Ready must disappear.
        relaunchedAppState.noteSystemAudioPermissionRequestStarted()
        #expect(relaunchedAppState.isSystemAudioPermissionRequestInProgress)
        #expect(relaunchedAppState.permissionSnapshot.screenSystemAudio != .granted)
        #expect(!relaunchedAppState.isRecordingStartAllowed)
    }

    @Test
    func clearRecordingErrorIfPermissionsResolvedExitsErrorStateAfterGrant() async {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        let appState = AppState(
            recordingController: FailingRecordingController(
                error: RecordingControllerError.preflightFailed("Microphone access is required before recording.")
            ),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker(
                snapshot: RecorderPermissionSnapshot(
                    microphone: .notDetermined,
                    screenSystemAudio: .granted,
                    storage: .granted
                )
            )
        )

        await #expect(throws: RecordingControllerError.self) {
            try await appState.startRecording()
        }
        #expect(appState.status == .error)

        // Helper must not exit the error state while permissions are still
        // blocking.
        appState.clearRecordingErrorIfPermissionsResolved()
        #expect(appState.status == .error)

        // Now grant the missing permission. With the helper called, the
        // app should leave the Recording failed panel.
        let recoveredAppState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )
        await #expect(throws: Never.self) {
            try await recoveredAppState.startRecording()
            try await recoveredAppState.stopRecording()
        }
        // Simulate a stale preflight failure prior to granting permissions.
        recoveredAppState.applyTestErrorForPreflight()
        #expect(recoveredAppState.status == .error)

        recoveredAppState.clearRecordingErrorIfPermissionsResolved()
        #expect(recoveredAppState.status == .idle)
        #expect(recoveredAppState.errorMessage == nil)
    }

    @Test
    func clearRecordingErrorIfPermissionsResolvedRespectsPendingSystemAudioProbe() {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted
        )
        appState.applyTestErrorForPreflight()
        #expect(appState.status == .error)

        appState.noteSystemAudioPermissionRequestStarted()
        // While the probe is pending we must NOT clear the error: the
        // UI must remain in a blocked state until samples are verified.
        appState.clearRecordingErrorIfPermissionsResolved()
        #expect(appState.status == .error)

        appState.noteSystemAudioPermissionRequestSucceeded()
        appState.clearRecordingErrorIfPermissionsResolved()
        #expect(appState.status == .idle)
    }

    @Test
    func invalidateSystemAudioPermissionCacheDropsCachedGrantSoFixPermissionsReprobes() {
        UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        defer {
            UserDefaults.standard.removeObject(forKey: Self.currentSystemAudioProbeKey)
        }

        // First run: probe succeeds and the persisted flag is written.
        let firstAppState = AppState(
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
        firstAppState.noteSystemAudioPermissionRequestSucceeded()
        #expect(firstAppState.permissionSnapshot.screenSystemAudio == .granted)

        // Second launch: persisted flag still grants. But the user then
        // clicks Fix Permissions and the system must re-verify.
        let relaunchedAppState = AppState(
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
        #expect(relaunchedAppState.permissionSnapshot.screenSystemAudio == .granted)

        relaunchedAppState.invalidateSystemAudioPermissionCache()

        #expect(relaunchedAppState.permissionSnapshot.screenSystemAudio == .notDetermined)
        #expect(!relaunchedAppState.isRecordingStartAllowed)
        // Persisted UserDefaults entry must also be cleared so a third
        // launch does not auto-grant again.
        #expect(UserDefaults.standard.bool(forKey: Self.currentSystemAudioProbeKey) == false)
    }

    @Test
    func systemAudioFormatterReportsCheckingWhileProbePending() {
        #expect(
            RecordingDisplayFormatter.systemAudioText(
                isEnabled: true,
                permissionState: .granted,
                captureStatus: .idle,
                recordingStatus: .idle,
                isPermissionRequestInProgress: true
            ) == "Checking permission"
        )
        #expect(
            RecordingDisplayFormatter.systemAudioText(
                isEnabled: true,
                permissionState: .notDetermined,
                captureStatus: .idle,
                recordingStatus: .idle,
                isPermissionRequestInProgress: true
            ) == "Checking permission"
        )
    }

    @Test
    func permissionOnboardingFeedbackKeepsChecklistVisibleAfterSilentSystemAudioProbe() {
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

        #expect(appState.shouldShowPermissionsOnboarding)
        appState.beginPermissionOnboarding(message: "Checking recording permissions...")
        appState.noteSystemAudioPermissionRequestSucceeded()
        appState.completePermissionOnboarding(
            message: "Microphone and system audio access are ready.",
            clearAfter: nil
        )

        #expect(!appState.shouldShowPermissionsOnboarding)
        #expect(appState.shouldShowPermissionChecklist)
        #expect(appState.permissionOnboardingMessage == "Microphone and system audio access are ready.")

        appState.clearPermissionOnboardingFeedback()

        #expect(!appState.shouldShowPermissionChecklist)
        #expect(appState.permissionOnboardingMessage == nil)
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

    @Test
    func airPodsOnlyInputBlocksRecordingStartWithExplicitReason() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: {
                [MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")]
            }
        )

        #expect(appState.selectedMicrophoneName == "No input device")
        #expect(appState.microphoneSelectionReason == "AirPods/Bluetooth microphone is blocked for recording. Connect the MacBook or USB microphone.")
        #expect(appState.recordingStartBlockingReason == "AirPods/Bluetooth microphone is blocked for recording. Connect the MacBook or USB microphone.")
        #expect(!appState.isRecordingStartAllowed)
    }

    @Test
    func teamsVirtualInputOnlyBlocksRecordingStartWithExplicitReason() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: {
                [MicrophoneInputDevice(id: "teams-audio", name: "Microsoft Teams Audio")]
            }
        )

        #expect(appState.selectedMicrophoneName == "No input device")
        #expect(appState.microphoneSelectionReason == DevicePriorityResolver.virtualInputBlockedWarning)
        #expect(appState.recordingStartBlockingReason == DevicePriorityResolver.virtualInputBlockedWarning)
        #expect(!appState.isRecordingStartAllowed)
    }

    @Test
    func savedPreferredTeamsVirtualInputIsClearedAndBuiltInIsSelected() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: {
                [
                    MicrophoneInputDevice(id: "teams-audio", name: "Microsoft Teams Audio"),
                    MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
                ]
            },
            appSettings: AppSettings(
                recording: RecordingSettings(microphoneDeviceID: "teams-audio")
            )
        )

        #expect(appState.recordingSettings.microphoneDeviceID == nil)
        #expect(appState.selectedMicrophoneName == "MacBook Pro Microphone")
        #expect(appState.microphoneSelectionReason == "Virtual meeting microphone avoided because built-in microphone is available.")
    }

    @Test
    func selectingPreferredAirPodsClearsManualMicrophonePreference() {
        let appState = AppState(
            recordingController: StubRecordingController(),
            outputFolderURL: Self.testOutputFolder(),
            permissionChecker: StaticPermissionChecker.allGranted,
            microphoneDeviceProvider: {
                [
                    MicrophoneInputDevice(id: "airpods", name: "AirPods Pro"),
                    MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
                ]
            }
        )

        appState.setPreferredMicrophoneDeviceID("airpods")

        #expect(appState.recordingSettings.microphoneDeviceID == nil)
        #expect(appState.selectedMicrophoneName == "MacBook Pro Microphone")
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
        AppState.systemAudioPermissionProbeSucceededKeyForTesting
    }

    private static func sanitized(_ value: String) -> String {
        value
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: ":", with: "_")
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
