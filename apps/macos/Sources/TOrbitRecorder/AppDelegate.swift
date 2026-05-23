import AppKit
import Combine
import TOrbitRecorderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var startItem: NSMenuItem?
    private var stopItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        configureStatusItem()
        bindState()
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

        let openFolderItem = NSMenuItem(
            title: "Open Recordings Folder",
            action: #selector(openRecordingsFolder),
            keyEquivalent: ""
        )
        openFolderItem.target = self
        menu.addItem(openFolderItem)

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
    }

    private func refreshMenuState() {
        startItem?.isEnabled = appState.status != .recording
        stopItem?.isEnabled = appState.status == .recording
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
            } catch {
                AppLogger.recording.error("Menu stop failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    @objc private func openRecordingsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
            AppLogger.storage.info("Opened recordings folder")
        } catch {
            AppLogger.storage.error("Failed to open recordings folder: \(String(describing: error), privacy: .public)")
        }
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func quit() {
        AppLogger.app.info("TOrbitRecorder quit requested")
        NSApp.terminate(nil)
    }
}
