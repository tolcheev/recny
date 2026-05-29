import AppKit
import Combine
import SwiftUI
import TOrbitRecorderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var appState = AppState(appSettings: AppSettingsStore.load())

    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var recordingToggleItem: NSMenuItem?
    private var permissionAttentionItem: NSMenuItem?
    private var permissionAttentionSeparatorItem: NSMenuItem?
    private var playLastItem: NSMenuItem?
    private var openLastFolderItem: NSMenuItem?
    private var captureScreenshotItem: NSMenuItem?
    private var fallbackMainWindow: NSWindow?
    private var isTerminatingAfterRecordingStop = false
    private var globalHotKeyController: GlobalHotKeyController?
    private var screenshotHotKeyController: ScreenshotHotKeyController?
    private var didSurfacePermissionAttentionThisLaunch = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard enforceSingleRunningInstance() else {
            return
        }

        applyActivationPolicy()
        configureStatusItem()
        bindState()
        syncLaunchAtLoginPreferenceOnLaunch()
        appState.startAutoStartMonitoring()
        appState.startMicrophoneDeviceMonitoring()
        startGlobalHotKey()
        startScreenshotHotKey()
        AppLogger.app.info("T-Orbit Recorder launched")
        AppLogger.file(.info, category: "app", "app start version=\(BuildInfo.appVersion) commit=\(BuildInfo.gitCommit)")
        surfaceRecordingPermissionProblemIfNeeded(reason: "launch")
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalHotKeyController?.stop()
        screenshotHotKeyController?.stop()
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
        if UserDefaults.standard.object(forKey: MenuBarStatusItemPlacement.preferredPositionKey) == nil {
            UserDefaults.standard.set(
                MenuBarStatusItemPlacement.defaultPreferredPosition,
                forKey: MenuBarStatusItemPlacement.preferredPositionKey
            )
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let statusItem else {
            return
        }

        statusItem.autosaveName = MenuBarStatusItemPlacement.autosaveName
        statusItem.isVisible = true

        if let button = statusItem.button {
            button.image = menuBarImage(
                symbolName: "play",
                accessibilityDescription: "T-Orbit Recorder"
            )
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "T-Orbit Recorder (\(KeyboardShortcutCatalog.showWindowGlobal.displayText))"
        }

        let menu = NSMenu()

        let showWindowItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showWindow),
            keyEquivalent: KeyboardShortcutCatalog.showWindowGlobal.keyEquivalent
        )
        showWindowItem.target = self
        showWindowItem.keyEquivalentModifierMask = [.control, .option]
        menu.addItem(showWindowItem)

        let permissionAttentionItem = NSMenuItem(
            title: "Recording Blocked: Fix Permissions",
            action: #selector(fixRecordingPermissions),
            keyEquivalent: ""
        )
        permissionAttentionItem.target = self
        permissionAttentionItem.isHidden = true
        menu.addItem(permissionAttentionItem)
        self.permissionAttentionItem = permissionAttentionItem

        let permissionAttentionSeparatorItem = NSMenuItem.separator()
        permissionAttentionSeparatorItem.isHidden = true
        menu.addItem(permissionAttentionSeparatorItem)
        self.permissionAttentionSeparatorItem = permissionAttentionSeparatorItem

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

        let captureScreenshotItem = NSMenuItem(
            title: "Capture Full Screenshot",
            action: #selector(captureScreenshotFromMenu),
            keyEquivalent: KeyboardShortcutCatalog.captureScreenshot.keyEquivalent
        )
        captureScreenshotItem.target = self
        captureScreenshotItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureScreenshotItem)
        self.captureScreenshotItem = captureScreenshotItem

        let openLastFolderItem = NSMenuItem(
            title: "Open Library",
            action: #selector(openLastRecordingFolder),
            keyEquivalent: KeyboardShortcutCatalog.openLatestRecordingFolder.keyEquivalent
        )
        openLastFolderItem.target = self
        openLastFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openLastFolderItem)
        self.openLastFolderItem = openLastFolderItem

        let openLibraryItem = NSMenuItem(
            title: "Open Records",
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

        appState.$currentSessionFolderURL
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

        appState.$recordingSettings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        appState.$permissionSnapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                    self?.surfaceRecordingPermissionProblemIfNeeded(reason: "permission_snapshot")
                }
            }
            .store(in: &cancellables)

        appState.$isSystemAudioPermissionRequestInProgress
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AppWindowRequest.showMainWindowNotificationName)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.showMainWindow()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshMenuState() {
        let needsPermissionAttention = needsRecordingPermissionAttention
        let displayState = MenuBarDisplayStatePresenter.state(
            recordingStatus: appState.status,
            hasPlayableLastRecording: hasPlayableLastRecording,
            hasLastRecording: appState.lastRecording != nil,
            showRecordingIndicator: appState.privacySettings.showRecordingIndicator,
            needsRecordingPermissions: needsPermissionAttention
        )

        recordingToggleItem?.title = appState.isStoppingRecording ? "Stopping..." : displayState.recordingToggleTitle
        switch displayState.recordingToggleAction {
        case .stop:
            recordingToggleItem?.action = #selector(stopRecording)
        case .start:
            recordingToggleItem?.action = #selector(startRecording)
        case .fixPermissions:
            recordingToggleItem?.action = #selector(fixRecordingPermissions)
        }
        recordingToggleItem?.isEnabled = !appState.isStoppingRecording
        permissionAttentionItem?.isHidden = !needsPermissionAttention
        permissionAttentionSeparatorItem?.isHidden = !needsPermissionAttention
        permissionAttentionItem?.attributedTitle = NSAttributedString(
            string: "Recording Blocked: Fix Permissions",
            attributes: [
                .font: NSFont.menuFont(ofSize: 0),
                .foregroundColor: NSColor.systemRed
            ]
        )
        playLastItem?.isEnabled = displayState.canPlayLastRecording
        openLastFolderItem?.isEnabled = true
        captureScreenshotItem?.isEnabled = appState.preferredScreenshotFolderURL != nil
        statusItem?.button?.image = menuBarImage(
            symbolName: displayState.symbolName,
            accessibilityDescription: displayState.accessibilityDescription
        )
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.title = displayState.statusItemTitle
        statusItem?.button?.toolTip = "\(displayState.accessibilityDescription) (\(KeyboardShortcutCatalog.showWindowGlobal.displayText))"
        statusItem?.button?.contentTintColor = nil
    }

    private func applyActivationPolicy() {
        NSApp.setActivationPolicy(appState.privacySettings.showDockIcon ? .regular : .accessory)
    }

    private func menuBarImage(symbolName: String, accessibilityDescription: String) -> NSImage? {
        if symbolName == "permission.question" {
            return permissionQuestionMenuBarImage(accessibilityDescription: accessibilityDescription)
        }

        if symbolName == "play" || symbolName == "play.fill" {
            return playMenuBarImage(
                isFilled: symbolName == "play.fill",
                accessibilityDescription: accessibilityDescription
            )
        }

        if let image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        ) {
            let configuredImage = image.withSymbolConfiguration(
                NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
            ) ?? image
            configuredImage.isTemplate = true
            return configuredImage
        }

        return playMenuBarImage(
            isFilled: symbolName == "play.fill",
            accessibilityDescription: accessibilityDescription
        )
    }

    private var needsRecordingPermissionAttention: Bool {
        if appState.permissionSnapshot.microphone != .granted {
            return true
        }

        guard appState.recordingSettings.systemAudioEnabled else {
            return false
        }

        return appState.isSystemAudioPermissionRequestInProgress
            || appState.permissionSnapshot.screenSystemAudio != .granted
    }

    private func playMenuBarImage(
        isFilled: Bool,
        accessibilityDescription: String
    ) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.accessibilityDescription = accessibilityDescription
        image.lockFocus()

        NSColor.white.setStroke()
        NSColor.white.setFill()

        let play = NSBezierPath()
        play.move(to: NSPoint(x: 5.85, y: 3.7))
        play.line(to: NSPoint(x: 5.85, y: 14.3))
        play.line(to: NSPoint(x: 14.75, y: 9))
        play.close()
        play.lineJoinStyle = .round

        if isFilled {
            play.fill()
        } else {
            play.lineWidth = 1.45
            play.stroke()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func permissionQuestionMenuBarImage(accessibilityDescription: String) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18))
        image.accessibilityDescription = accessibilityDescription
        image.lockFocus()

        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowOffset = NSSize(width: 0, height: -0.5)
        shadow.shadowBlurRadius = 1.0
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 21, weight: .heavy),
            .foregroundColor: NSColor.systemRed,
            .paragraphStyle: paragraph,
            .shadow: shadow
        ]
        NSString(string: "?").draw(
            in: NSRect(x: 0, y: -3.2, width: 18, height: 23),
            withAttributes: attributes
        )

        image.unlockFocus()
        image.isTemplate = false
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
                showMainWindow()
            }
        }
    }

    @objc private func fixRecordingPermissions() {
        AppLogger.file(.warning, category: "permissions", "fix permissions requested from menu bar")
        showMainWindow()
        PermissionActionHandler.handlePrimaryFixAction(appState: appState)
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
        openSettingsFromShortcut()
    }

    @objc private func showDiagnostics() {
        AppWindows.openDiagnostics(appState: appState)
    }

    @objc private func captureScreenshotFromMenu() {
        captureScreenshotFromShortcut()
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

    func openSettingsFromShortcut() {
        AppLogger.file(.info, category: "app", "open settings")
        AppWindows.openSettings(appState: appState)
    }

    func captureScreenshotFromShortcut() {
        AppLogger.file(.info, category: "app", "keyboard shortcut \(KeyboardShortcutCatalog.captureScreenshot.displayText)")
        captureScreenshotForPreferredFolder(source: "app_active_shortcut")
    }

    private func captureScreenshotFromGlobalHotKey() {
        AppLogger.file(.info, category: "app", "global hotkey \(KeyboardShortcutCatalog.captureScreenshotGlobal.displayText)")
        captureScreenshotForPreferredFolder(source: "global_hotkey")
    }

    private func showWindowFromGlobalHotKey() {
        AppLogger.file(.info, category: "app", "global hotkey \(KeyboardShortcutCatalog.showWindowGlobal.displayText)")
        showMainWindow()
    }

    private func surfaceRecordingPermissionProblemIfNeeded(reason: String) {
        if !needsRecordingPermissionAttention {
            didSurfacePermissionAttentionThisLaunch = false
            return
        }

        guard !didSurfacePermissionAttentionThisLaunch,
              !appState.isPermissionOnboardingInProgress,
              !appState.isSystemAudioPermissionRequestInProgress
        else {
            return
        }

        didSurfacePermissionAttentionThisLaunch = true
        AppLogger.file(.warning, category: "permissions", "recording unavailable surfaced reason=\(reason) message=\(appState.recordingStartBlockingReason ?? "unknown")")
        showMainWindow()
        NSApp.requestUserAttention(.criticalRequest)
    }

    func addMarkerFromShortcut(_ kind: RecordingMarkerKind) {
        guard appState.status == .recording else {
            return
        }

        if let marker = appState.addMarker(kind) {
            AppLogger.file(.info, category: "app", "keyboard shortcut Cmd+\(kind.shortcutKey) marker=\(marker.label)")
        }
    }

    private func startScreenshotHotKey() {
        let controller = ScreenshotHotKeyController { [weak self] in
            self?.captureScreenshotFromGlobalHotKey()
        }
        controller.start()
        screenshotHotKeyController = controller
    }

    private func startGlobalHotKey() {
        let controller = GlobalHotKeyController { [weak self] in
            self?.showWindowFromGlobalHotKey()
        }
        controller.start()
        globalHotKeyController = controller
    }

    private func captureScreenshotForPreferredFolder(source: String) {
        guard let sessionFolderURL = appState.preferredScreenshotFolderURL else {
            AppLogger.file(.warning, category: "app", "screenshot ignored source=\(source) reason=no_recording_folder")
            return
        }

        Task {
            do {
                let screenshotURL = try await NativeScreenshotCapture.captureFullScreen(
                    sessionFolderURL: sessionFolderURL
                )
                AppLogger.file(.info, category: "app", "screenshot saved source=\(source) path=\(screenshotURL.path(percentEncoded: false))")
            } catch NativeScreenshotError.cancelled {
                AppLogger.file(.info, category: "app", "screenshot cancelled source=\(source)")
            } catch {
                AppLogger.file(.error, category: "app", "screenshot failed source=\(source) error=\(String(describing: error))")
            }
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
        AppWindowCentering.centerAfterPresentation(mainWindow)
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
