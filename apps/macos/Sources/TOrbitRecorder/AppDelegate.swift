import AppKit
import Combine
import TOrbitRecorderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var appState = AppState(appSettings: AppSettingsStore.load())

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var startItem: NSMenuItem?
    private var stopItem: NSMenuItem?
    private var openLatestItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        bindState()
        appState.startAutoStartMonitoring()
        AppLogger.app.info("TOrbitRecorder launched")
    }

    private func configureStatusItem() {
        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "record.circle",
                accessibilityDescription: "TOrbitRecorder"
            )
            button.toolTip = "TOrbitRecorder"
        }

        let menu = NSMenu()

        let showWindowItem = NSMenuItem(
            title: "Show Window",
            action: #selector(showWindow),
            keyEquivalent: ""
        )
        showWindowItem.target = self
        menu.addItem(showWindowItem)

        menu.addItem(.separator())

        let startItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: ""
        )
        startItem.target = self
        menu.addItem(startItem)
        self.startItem = startItem

        let stopItem = NSMenuItem(
            title: "Stop Recording",
            action: #selector(stopRecording),
            keyEquivalent: ""
        )
        stopItem.target = self
        menu.addItem(stopItem)
        self.stopItem = stopItem

        menu.addItem(.separator())

        let openLatestItem = NSMenuItem(
            title: "Open Latest Recording",
            action: #selector(openLatestRecording),
            keyEquivalent: ""
        )
        openLatestItem.target = self
        menu.addItem(openLatestItem)
        self.openLatestItem = openLatestItem

        let openLibraryItem = NSMenuItem(
            title: "Open Library",
            action: #selector(openLibrary),
            keyEquivalent: ""
        )
        openLibraryItem.target = self
        menu.addItem(openLibraryItem)

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(showSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

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

        appState.$privacySettings
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in
                    self?.refreshMenuState()
                }
            }
            .store(in: &cancellables)
    }

    private func refreshMenuState() {
        startItem?.isEnabled = appState.status != .recording
        stopItem?.isEnabled = appState.status == .recording
        openLatestItem?.isEnabled = appState.lastRecording != nil
        let symbolName = appState.status == .recording && appState.privacySettings.showRecordingIndicator
            ? "record.circle.fill"
            : "record.circle"
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: "TOrbitRecorder"
        )
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
        Task {
            do {
                try await appState.stopRecording()
                showMainWindow()
            } catch {
                AppLogger.recording.error("Menu stop failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @objc private func openLatestRecording() {
        guard let lastRecording = appState.lastRecording else {
            openLibrary()
            return
        }

        NSWorkspace.shared.open(lastRecording.sessionFolderURL)
        AppLogger.storage.info("Opened latest recording folder")
    }

    @objc private func openLibrary() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
            AppLogger.storage.info("Opened recording library")
        } catch {
            AppLogger.storage.error("Failed to open recording library: \(String(describing: error), privacy: .public)")
        }
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.title == "TOrbitRecorder"
        } ?? NSApp.windows.first

        mainWindow?.makeKeyAndOrderFront(nil)
        mainWindow?.orderFrontRegardless()
    }

    @objc private func quit() {
        AppLogger.app.info("TOrbitRecorder quit requested")
        NSApp.terminate(nil)
    }
}
