import AppKit
import Combine
import SwiftUI
import TOrbitRecorderCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var appState = AppState(appSettings: AppSettingsStore.load())

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private lazy var globalHotKeyController = GlobalHotKeyController { [weak self] in
        self?.showMainWindow()
    }
    private var cancellables: Set<AnyCancellable> = []
    private var recordingToggleItem: NSMenuItem?
    private var playLastItem: NSMenuItem?
    private var openLastFolderItem: NSMenuItem?
    private var fallbackMainWindow: NSWindow?
    private var isTerminatingAfterRecordingStop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleRunningInstance() else {
            return
        }

        applyActivationPolicy()
        configureStatusItem()
        bindState()
        globalHotKeyController.start()
        Self.requestNotificationAuthorization()
        syncLaunchAtLoginPreferenceOnLaunch()
        appState.startAutoStartMonitoring()
        appState.startMicrophoneDeviceMonitoring()
        AppLogger.app.info("T-Orbit Recorder launched")
        AppLogger.file(.info, category: "app", "app start version=\(BuildInfo.appVersion) commit=\(BuildInfo.gitCommit)")
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController.stop()
        AppLogger.file(.info, category: "app", "app stop")
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard appState.status == .recording,
              !isTerminatingAfterRecordingStop
        else {
            return .terminateNow
        }

        confirmStopAndQuit()
        return .terminateCancel
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = menuBarImage(
                symbolName: "waveform.circle",
                accessibilityDescription: "T-Orbit Recorder"
            )
            button.imagePosition = .imageOnly
            button.toolTip = "T-Orbit Recorder"
        }

        let menu = NSMenu()

        let showWindowItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showWindow),
            keyEquivalent: KeyboardShortcutCatalog.showWindowGlobal.keyEquivalent
        )
        showWindowItem.target = self
        showWindowItem.keyEquivalentModifierMask = [.option]
        menu.addItem(showWindowItem)

        menu.addItem(.separator())

        let recordingToggleItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: KeyboardShortcutCatalog.toggleRecording.keyEquivalent
        )
        recordingToggleItem.target = self
        recordingToggleItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(recordingToggleItem)
        self.recordingToggleItem = recordingToggleItem

        menu.addItem(.separator())

        let playLastItem = NSMenuItem(
            title: "Play Last Recording",
            action: #selector(playLastRecording),
            keyEquivalent: ""
        )
        playLastItem.target = self
        menu.addItem(playLastItem)
        self.playLastItem = playLastItem

        let openLastFolderItem = NSMenuItem(
            title: "Open Recordings",
            action: #selector(openLastRecordingFolder),
            keyEquivalent: KeyboardShortcutCatalog.openLatestRecordingFolder.keyEquivalent
        )
        openLastFolderItem.target = self
        openLastFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openLastFolderItem)
        self.openLastFolderItem = openLastFolderItem

        let openLibraryItem = NSMenuItem(
            title: "Open Library",
            action: #selector(openLibrary),
            keyEquivalent: KeyboardShortcutCatalog.openLibrary.keyEquivalent
        )
        openLibraryItem.target = self
        openLibraryItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openLibraryItem)

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics",
            action: #selector(showDiagnostics),
            keyEquivalent: KeyboardShortcutCatalog.openDiagnostics.keyEquivalent
        )
        diagnosticsItem.target = self
        diagnosticsItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(diagnosticsItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
        refreshMenuState()
    }

    private func bindState() {
        appState.$status
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        appState.$lastRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        appState.$isStoppingRecording
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        appState.$privacySettings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.applyActivationPolicy()
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        appState.$autoStartNotificationMessage
            .compactMap { $0 }
            .receive(on: RunLoop.main)
            .sink { message in
                Self.deliverNotification(message)
            }
            .store(in: &cancellables)
    }

    private nonisolated static func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound],
            completionHandler: handleNotificationAuthorization
        )
    }

    private nonisolated static func handleNotificationAuthorization(granted: Bool, error: Error?) {
        if let error {
            AppLogger.app.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
        } else {
            AppLogger.app.info("Notification authorization status: \(granted, privacy: .public)")
        }
    }

    private nonisolated static func deliverNotification(_ message: String) {
        let content = UNMutableNotificationContent()
        content.title = "T-Orbit Recorder"
        content.body = message
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: "torbit-recorder-autostart-\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(
            request,
            withCompletionHandler: handleNotificationDelivery
        )
    }

    private nonisolated static func handleNotificationDelivery(error: Error?) {
        if let error {
            AppLogger.app.error("Failed to deliver notification: \(String(describing: error), privacy: .public)")
        }
    }

    private func refreshMenuState() {
        let displayState = MenuBarDisplayStatePresenter.state(
            recordingStatus: appState.status,
            hasPlayableLastRecording: hasPlayableLastRecording,
            hasLastRecording: appState.lastRecording != nil,
            showRecordingIndicator: appState.privacySettings.showRecordingIndicator
        )

        recordingToggleItem?.title = appState.isStoppingRecording ? "Stopping..." : displayState.recordingToggleTitle
        recordingToggleItem?.action = displayState.recordingToggleAction == .stop
            ? #selector(stopRecording)
            : #selector(startRecording)
        recordingToggleItem?.isEnabled = !appState.isStoppingRecording
        playLastItem?.isEnabled = displayState.canPlayLastRecording
        openLastFolderItem?.isEnabled = true
        statusItem.button?.image = menuBarImage(
            symbolName: displayState.symbolName,
            accessibilityDescription: displayState.accessibilityDescription
        )
        statusItem.button?.contentTintColor = switch displayState.tint {
        case .recording:
            .systemRed
        case .error:
            .systemOrange
        case .none:
            nil
        }
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(appState.privacySettings.showDockIcon ? .regular : .accessory)
    }

    private func menuBarImage(symbolName: String, accessibilityDescription: String) -> NSImage? {
        let iconState: MenuBarIconState
        if symbolName.contains("exclamationmark") {
            iconState = .error
        } else if symbolName.contains("fill") {
            iconState = .recording
        } else {
            iconState = .idle
        }

        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.accessibilityDescription = accessibilityDescription
        image.lockFocus()

        let strokeColor = NSColor.black
        strokeColor.setStroke()
        strokeColor.setFill()

        let outerRect = NSRect(x: 2.5, y: 3, width: 13, height: 12)
        let outerPath = NSBezierPath(roundedRect: outerRect, xRadius: 3.5, yRadius: 3.5)
        outerPath.lineWidth = 1.8
        outerPath.stroke()

        switch iconState {
        case .idle:
            let center = NSBezierPath(ovalIn: NSRect(x: 6.25, y: 6.25, width: 5.5, height: 5.5))
            center.lineWidth = 1.6
            center.stroke()
        case .recording:
            NSBezierPath(ovalIn: NSRect(x: 5.7, y: 5.7, width: 6.6, height: 6.6)).fill()
        case .error:
            let indicator = NSBezierPath()
            indicator.lineWidth = 1.8
            indicator.move(to: NSPoint(x: 9, y: 11.7))
            indicator.line(to: NSPoint(x: 9, y: 7.2))
            indicator.stroke()
            NSBezierPath(ovalIn: NSRect(x: 8.1, y: 4.9, width: 1.8, height: 1.8)).fill()
        }

        image.unlockFocus()
        image.isTemplate = true
        return image
    }

    private func syncLaunchAtLoginPreferenceOnLaunch() {
        guard appState.privacySettings.launchAtLogin else {
            return
        }

        do {
            let snapshot = try LaunchAtLoginController.setEnabled(true)
            appState.setLaunchAtLoginPreference(snapshot.isOn)
            AppLogger.file(.info, category: "app", "launch at login startup sync enabled=\(snapshot.isOn) message=\(snapshot.message)")
        } catch {
            let errorMessage = LaunchAtLoginController.humanReadableError(error)
            appState.setLaunchAtLoginPreference(true, errorMessage: errorMessage)
            AppLogger.file(.error, category: "app", "launch at login startup sync failed error=\(String(describing: error))")
        }
    }

    private func enforceSingleRunningInstance() -> Bool {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? "com.torbit.recorder"
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let runningInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map {
                RunningAppInstance(
                    processID: $0.processIdentifier,
                    bundlePath: $0.bundleURL?.path(percentEncoded: false)
                )
            }

        switch AppInstancePolicy.decision(
            currentProcessID: currentProcessID,
            runningInstances: runningInstances
        ) {
        case .continueCurrent:
            return true
        case .terminateCurrentAndActivateExisting(let existingInstance):
            if let existingApp = NSRunningApplication(processIdentifier: existingInstance.processID) {
                existingApp.activate(options: [.activateAllWindows])
            }

            let duplicatePaths = AppInstancePolicy.userFacingBundlePathList(
                currentProcessID: currentProcessID,
                runningInstances: runningInstances
            )
            AppLogger.file(
                .warning,
                category: "app",
                "duplicate instance blocked current=\(Bundle.main.bundleURL.path(percentEncoded: false)) existing=\(existingInstance.bundlePath ?? "unknown") all_existing=\(duplicatePaths.joined(separator: " | "))"
            )
            showDuplicateInstanceAlert(existingPaths: duplicatePaths)
            NSApp.terminate(nil)
            return false
        }
    }

    private func showDuplicateInstanceAlert(existingPaths: [String]) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Another T-Orbit Recorder copy is already running"
        let pathText = existingPaths.isEmpty
            ? "A previous T-Orbit Recorder process is still active."
            : "Running copy:\n\(existingPaths.joined(separator: "\n"))"
        alert.informativeText = """
        \(pathText)

        Quit all T-Orbit Recorder copies, then open /Applications/TOrbitRecorder.app. Running .build, dist, and /Applications copies at the same time can make macOS ask for audio permissions again.
        """
        alert.addButton(withTitle: "Quit This Copy")
        alert.runModal()
    }

    @objc private func showWindow() {
        showMainWindow()
    }

    @objc private func startRecording() {
        Task {
            do {
                try await appState.startRecording()
            } catch {
                AppLogger.recording.error("Menu start failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @objc private func stopRecording() {
        AppLogger.file(.info, category: "recording", "stop requested source=menu")
        Task {
            do {
                try await appState.stopRecording()
                showMainWindow()
            } catch {
                AppLogger.recording.error("Menu stop failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @objc private func playLastRecording() {
        guard let lastRecording = appState.lastRecording,
              let playback = RecordingPlaybackResolver.preferredPlayback(
                sessionFolderURL: lastRecording.sessionFolderURL
              )
        else {
            return
        }

        AppWindows.openAudioPlayer(
            url: playback.url,
            title: "\(lastRecording.title) - \(playback.kind.displayName)"
        )
        AppLogger.storage.info("Opened latest recording in app player")
    }

    @objc private func openLastRecordingFolder() {
        AppWindows.openRecordingsFolder(appState: appState)
        AppLogger.storage.info("Opened recordings folder")
    }

    @objc private func openLibrary() {
        AppWindows.openLibrary(appState: appState)
    }

    @objc private func showSettings() {
        AppWindows.openSettings(appState: appState)
    }

    @objc private func showDiagnostics() {
        AppWindows.openDiagnostics(appState: appState)
    }

    func toggleRecordingFromShortcut() {
        AppLogger.file(.info, category: "app", "keyboard shortcut \(KeyboardShortcutCatalog.toggleRecording.displayText)")
        guard !appState.isStoppingRecording else {
            AppLogger.file(.info, category: "recording", "ignored stop/start shortcut while stop is in progress")
            return
        }

        if appState.status == .recording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func openLatestRecordingFolderFromShortcut() {
        AppLogger.file(.info, category: "app", "keyboard shortcut \(KeyboardShortcutCatalog.openLatestRecordingFolder.displayText)")
        openLastRecordingFolder()
    }

    func openLibraryFromShortcut() {
        AppLogger.file(.info, category: "app", "keyboard shortcut \(KeyboardShortcutCatalog.openLibrary.displayText)")
        openLibrary()
    }

    func openDiagnosticsFromShortcut() {
        AppLogger.file(.info, category: "app", "keyboard shortcut \(KeyboardShortcutCatalog.openDiagnostics.displayText)")
        showDiagnostics()
    }

    func addMarkerFromShortcut(_ kind: RecordingMarkerKind) {
        guard appState.status == .recording else {
            return
        }

        if let marker = appState.addMarker(kind) {
            AppLogger.file(.info, category: "app", "keyboard shortcut Cmd+\(kind.shortcutKey) marker=\(marker.label)")
        }
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.identifier == .torbitMainWindow || window.title == "T-Orbit Recorder" || window.title == "TOrbit Recorder"
        } ?? fallbackMainWindow ?? makeFallbackMainWindow()

        mainWindow.identifier = .torbitMainWindow
        mainWindow.isReleasedWhenClosed = false
        mainWindow.makeKeyAndOrderFront(nil)
        mainWindow.orderFrontRegardless()
    }

    private func makeFallbackMainWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "T-Orbit Recorder"
        window.identifier = .torbitMainWindow
        window.contentViewController = NSHostingController(rootView: MainRecorderView(appState: appState))
        window.isReleasedWhenClosed = false
        window.center()
        fallbackMainWindow = window
        return window
    }

    private var hasPlayableLastRecording: Bool {
        guard let lastRecording = appState.lastRecording else {
            return false
        }

        return FileManager.default.fileExists(atPath: lastRecording.mixedAudioURL.path(percentEncoded: false))
    }

    @objc private func quit() {
        AppLogger.app.info("T-Orbit Recorder quit requested")
        AppLogger.file(.info, category: "app", "quit requested")
        NSApp.terminate(nil)
    }

    private func confirmStopAndQuit() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Recording is active. Stop and quit?"
        alert.informativeText = "T-Orbit Recorder will stop the current recording before quitting."
        alert.addButton(withTitle: "Stop and Quit")
        alert.addButton(withTitle: "Cancel")

        guard alert.runModal() == .alertFirstButtonReturn else {
            AppLogger.app.info("Quit cancelled while recording is active")
            AppLogger.file(.info, category: "app", "quit cancelled while recording is active")
            return
        }

        Task {
            do {
                try await appState.stopRecording()
                AppLogger.app.info("Active recording stopped before quit")
                AppLogger.file(.info, category: "recording", "active recording stopped before quit")
                isTerminatingAfterRecordingStop = true
                NSApp.terminate(nil)
            } catch {
                isTerminatingAfterRecordingStop = false
                AppLogger.recording.error("Failed to stop recording before quit: \(String(describing: error), privacy: .public)")
                AppLogger.file(.error, category: "recording", "failed to stop recording before quit error=\(String(describing: error))")
                showMainWindow()
            }
        }
    }
}

private extension NSUserInterfaceItemIdentifier {
    static let torbitMainWindow = NSUserInterfaceItemIdentifier("com.torbit.recorder.main-window")
}

private enum MenuBarIconState {
    case idle
    case recording
    case error
}
