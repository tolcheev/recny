import AppKit
import Combine
import SwiftUI
import RecnyCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var appState = AppState(appSettings: AppSettingsStore.load())

    private var statusItem: NSStatusItem?
    private var cancellables: Set<AnyCancellable> = []
    private var recordingToggleItem: NSMenuItem?
    private var permissionAttentionItem: NSMenuItem?
    private var permissionAttentionSeparatorItem: NSMenuItem?
    private var updateAvailableItem: NSMenuItem?
    private var updateLaterItem: NSMenuItem?
    private var updateSkipItem: NSMenuItem?
    private var updateSeparatorItem: NSMenuItem?
    private var playLastItem: NSMenuItem?
    private var openLastFolderItem: NSMenuItem?
    private var captureScreenshotItem: NSMenuItem?
    private var fallbackMainWindow: NSWindow?
    private var isTerminatingAfterRecordingStop = false
    private var globalHotKeyController: GlobalHotKeyController?
    private var screenshotHotKeyController: ScreenshotHotKeyController?
    private var didSurfacePermissionAttentionThisLaunch = false
    private var updateReminderState = AppUpdateReminderStore.load()
    private var availableUpdateRelease: AppUpdateRelease?
    private var isCheckingForUpdates = false

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
        AppLogger.app.info("Recny launched")
        AppLogger.file(.info, category: "app", "app start version=\(BuildInfo.appVersion) commit=\(BuildInfo.gitCommit)")
        surfaceRecordingPermissionProblemIfNeeded(reason: "launch")
        runAutomaticUpdateCheckIfNeeded(reason: "launch")
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
                accessibilityDescription: "Recny"
            )
            button.title = ""
            button.imagePosition = .imageOnly
            button.toolTip = "Recny (\(KeyboardShortcutCatalog.showWindowGlobal.displayText))"
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

        let updateAvailableItem = NSMenuItem(
            title: "Update Available",
            action: #selector(openAvailableUpdate),
            keyEquivalent: ""
        )
        updateAvailableItem.target = self
        updateAvailableItem.isHidden = true
        menu.addItem(updateAvailableItem)
        self.updateAvailableItem = updateAvailableItem

        let updateLaterItem = NSMenuItem(
            title: "Remind Later",
            action: #selector(remindLaterForAvailableUpdate),
            keyEquivalent: ""
        )
        updateLaterItem.target = self
        updateLaterItem.isHidden = true
        menu.addItem(updateLaterItem)
        self.updateLaterItem = updateLaterItem

        let updateSkipItem = NSMenuItem(
            title: "Skip This Version",
            action: #selector(skipAvailableUpdate),
            keyEquivalent: ""
        )
        updateSkipItem.target = self
        updateSkipItem.isHidden = true
        menu.addItem(updateSkipItem)
        self.updateSkipItem = updateSkipItem

        let updateSeparatorItem = NSMenuItem.separator()
        updateSeparatorItem.isHidden = true
        menu.addItem(updateSeparatorItem)
        self.updateSeparatorItem = updateSeparatorItem

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

        let openLibraryItem = NSMenuItem(
            title: KeyboardShortcutCatalog.openLibrary.title,
            action: #selector(openLibrary),
            keyEquivalent: KeyboardShortcutCatalog.openLibrary.keyEquivalent
        )
        openLibraryItem.target = self
        openLibraryItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openLibraryItem)

        let playLastItem = NSMenuItem(
            title: "Play Last Recording",
            action: #selector(playLastRecording),
            keyEquivalent: ""
        )
        playLastItem.target = self
        menu.addItem(playLastItem)
        self.playLastItem = playLastItem

        let openLastFolderItem = NSMenuItem(
            title: KeyboardShortcutCatalog.openLatestRecordingFolder.title,
            action: #selector(openLastRecordingFolder),
            keyEquivalent: KeyboardShortcutCatalog.openLatestRecordingFolder.keyEquivalent
        )
        openLastFolderItem.target = self
        openLastFolderItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(openLastFolderItem)
        self.openLastFolderItem = openLastFolderItem

        let captureScreenshotItem = NSMenuItem(
            title: "Capture Full Screenshot",
            action: #selector(captureScreenshotFromMenu),
            keyEquivalent: KeyboardShortcutCatalog.captureScreenshot.keyEquivalent
        )
        captureScreenshotItem.target = self
        captureScreenshotItem.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(captureScreenshotItem)
        self.captureScreenshotItem = captureScreenshotItem

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

        let bugReportItem = NSMenuItem(
            title: "Report Bug",
            action: #selector(openBugReport),
            keyEquivalent: ""
        )
        bugReportItem.target = self
        menu.addItem(bugReportItem)

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
                    self?.runAutomaticUpdateCheckIfNeeded(reason: "status_change")
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

        NotificationCenter.default.publisher(for: AppUpdateEvents.updateDismissed)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let version = AppUpdateEvents.dismissedVersion(from: notification),
                          self?.availableUpdateRelease?.version == version
                    else {
                        return
                    }

                    self?.availableUpdateRelease = nil
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)

        NotificationCenter.default.publisher(for: AppUpdateEvents.updateAvailable)
            .receive(on: RunLoop.main)
            .sink { [weak self] notification in
                Task { @MainActor in
                    guard let release = AppUpdateEvents.release(from: notification),
                          self?.availableUpdateRelease?.version != release.version
                    else {
                        return
                    }

                    self?.availableUpdateRelease = release
                    self?.refreshMenuState()
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
            hasUpdateAvailable: availableUpdateRelease != nil,
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
        let shouldShowUpdate = availableUpdateRelease != nil
            && appState.status != .recording
            && !needsPermissionAttention
        if let availableUpdateRelease {
            updateAvailableItem?.title = "Update available: \(availableUpdateRelease.displayVersion)"
            updateAvailableItem?.attributedTitle = NSAttributedString(
                string: "Update available: \(availableUpdateRelease.displayVersion)",
                attributes: [
                    .font: NSFont.menuFont(ofSize: 0),
                    .foregroundColor: NSColor.systemBlue
                ]
            )
        }
        updateAvailableItem?.isHidden = !shouldShowUpdate
        updateLaterItem?.isHidden = !shouldShowUpdate
        updateSkipItem?.isHidden = !shouldShowUpdate
        updateSeparatorItem?.isHidden = !shouldShowUpdate
        playLastItem?.isEnabled = displayState.canPlayLastRecording
        openLastFolderItem?.isEnabled = true
        captureScreenshotItem?.isEnabled = appState.preferredScreenshotFolderURL != nil
        statusItem?.button?.image = menuBarImage(
            symbolName: displayState.symbolName,
            accessibilityDescription: displayState.accessibilityDescription
        )
        statusItem?.button?.imagePosition = .imageOnly
        statusItem?.button?.title = displayState.statusItemTitle
        if let availableUpdateRelease,
           displayState.tint == .update {
            statusItem?.button?.toolTip = "Recny update available: \(availableUpdateRelease.displayVersion) (\(KeyboardShortcutCatalog.showWindowGlobal.displayText))"
        } else {
            statusItem?.button?.toolTip = "\(displayState.accessibilityDescription) (\(KeyboardShortcutCatalog.showWindowGlobal.displayText))"
        }
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
                showsUpdateBadge: false,
                accessibilityDescription: accessibilityDescription
            )
        }

        if symbolName == "play.update" {
            return playMenuBarImage(
                isFilled: false,
                showsUpdateBadge: true,
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
        showsUpdateBadge: Bool = false,
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

        if showsUpdateBadge {
            NSColor.systemBlue.setFill()
            let badge = NSBezierPath(ovalIn: NSRect(x: 12.4, y: 12.1, width: 4.8, height: 4.8))
            badge.fill()
        }

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func runAutomaticUpdateCheckIfNeeded(reason: String) {
        let now = Date()
        guard AppUpdateReminderPolicy.shouldRunAutomaticCheck(
            now: now,
            state: updateReminderState,
            isRecording: appState.status == .recording
        ),
        !isCheckingForUpdates else {
            return
        }

        AppUpdateReminderPolicy.markAutomaticCheck(state: &updateReminderState, now: now)
        AppUpdateReminderStore.save(updateReminderState)
        isCheckingForUpdates = true

        Task {
            do {
                let result = try await AppUpdateChecker().check(
                    platform: .macOS,
                    currentVersion: BuildInfo.appVersion
                )
                let shouldSurface = AppUpdateReminderPolicy.shouldSurfaceUpdate(
                    result: result,
                    state: updateReminderState,
                    now: Date(),
                    isRecording: appState.status == .recording
                )

                await MainActor.run {
                    isCheckingForUpdates = false
                    if shouldSurface {
                        availableUpdateRelease = result.latestRelease
                        AppUpdateEvents.postAvailable(result.latestRelease)
                    }
                    refreshMenuState()
                    AppLogger.file(
                        .info,
                        category: "app",
                        "menu update check reason=\(reason) current=\(result.currentVersion) latest=\(result.latestRelease.version) available=\(result.isUpdateAvailable) surfaced=\(shouldSurface)"
                    )
                }
            } catch {
                await MainActor.run {
                    isCheckingForUpdates = false
                    AppLogger.file(.error, category: "app", "menu update check failed reason=\(reason) error=\(String(describing: error))")
                }
            }
        }
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
        alert.messageText = "Another Recny copy is already running"
        let pathText = existingPaths.isEmpty
            ? "A previous Recny process is still active."
            : "Running copy:\n\(existingPaths.joined(separator: "\n"))"
        alert.informativeText = """
        \(pathText)

        Quit all Recny copies, then open /Applications/Recny.app. Running .build, dist, and /Applications copies at the same time can make macOS ask for audio permissions again.
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

    @objc private func openBugReport() {
        guard let url = AppSupportLinks.bugReportURL(
            version: BuildInfo.appVersion,
            platform: .macOS
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    @objc private func openAvailableUpdate() {
        guard let availableUpdateRelease else {
            return
        }

        NSWorkspace.shared.open(availableUpdateRelease.downloadURL)
    }

    @objc private func remindLaterForAvailableUpdate() {
        guard let availableUpdateRelease else {
            return
        }

        AppUpdateReminderPolicy.remindLater(
            state: &updateReminderState,
            release: availableUpdateRelease,
            now: Date()
        )
        AppUpdateReminderStore.save(updateReminderState)
        let version = availableUpdateRelease.version
        self.availableUpdateRelease = nil
        AppUpdateEvents.postDismissed(version: version)
        refreshMenuState()
    }

    @objc private func skipAvailableUpdate() {
        guard let availableUpdateRelease else {
            return
        }

        AppUpdateReminderPolicy.skip(state: &updateReminderState, release: availableUpdateRelease)
        AppUpdateReminderStore.save(updateReminderState)
        let version = availableUpdateRelease.version
        self.availableUpdateRelease = nil
        AppUpdateEvents.postDismissed(version: version)
        refreshMenuState()
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
            window.identifier == .recnyMainWindow || window.title == "Recny" || window.title == "T-Orbit Recorder" || window.title == "TOrbit Recorder"
        } ?? fallbackMainWindow ?? makeFallbackMainWindow()

        mainWindow.identifier = .recnyMainWindow
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
        window.title = "Recny"
        window.identifier = .recnyMainWindow
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
        AppLogger.app.info("Recny quit requested")
        AppLogger.file(.info, category: "app", "quit requested")
        NSApp.terminate(nil)
    }

    private func confirmStopAndQuit() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Recording is active. Stop and quit?"
        alert.informativeText = "Recny will stop the current recording before quitting."
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
    static let recnyMainWindow = NSUserInterfaceItemIdentifier("com.torbit.recorder.main-window")
}
