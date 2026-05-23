import AppKit
import Combine
import SwiftUI
import TOrbitRecorderCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    lazy var appState = AppState(appSettings: AppSettingsStore.load())

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var cancellables: Set<AnyCancellable> = []
    private var recordingToggleItem: NSMenuItem?
    private var playLastItem: NSMenuItem?
    private var openLastFolderItem: NSMenuItem?
    private var fallbackMainWindow: NSWindow?

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

        let recordingToggleItem = NSMenuItem(
            title: "Start Recording",
            action: #selector(startRecording),
            keyEquivalent: ""
        )
        recordingToggleItem.target = self
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
            title: "Open Last Recording Folder",
            action: #selector(openLastRecordingFolder),
            keyEquivalent: ""
        )
        openLastFolderItem.target = self
        menu.addItem(openLastFolderItem)
        self.openLastFolderItem = openLastFolderItem

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

        let diagnosticsItem = NSMenuItem(
            title: "Diagnostics",
            action: #selector(showDiagnostics),
            keyEquivalent: ""
        )
        diagnosticsItem.target = self
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
        recordingToggleItem?.title = appState.status == .recording ? "Stop Recording" : "Start Recording"
        recordingToggleItem?.action = appState.status == .recording ? #selector(stopRecording) : #selector(startRecording)
        recordingToggleItem?.isEnabled = true
        playLastItem?.isEnabled = hasPlayableLastRecording
        openLastFolderItem?.isEnabled = appState.lastRecording != nil
        let symbolName: String
        let accessibilityDescription: String
        switch appState.status {
        case .recording where appState.privacySettings.showRecordingIndicator:
            symbolName = "record.circle.fill"
            accessibilityDescription = "TOrbit Recorder is recording"
        case .error:
            symbolName = "exclamationmark.circle.fill"
            accessibilityDescription = "TOrbit Recorder error"
        default:
            symbolName = "record.circle"
            accessibilityDescription = "TOrbit Recorder idle"
        }
        statusItem.button?.image = NSImage(
            systemSymbolName: symbolName,
            accessibilityDescription: accessibilityDescription
        )
        statusItem.button?.contentTintColor = switch appState.status {
        case .recording where appState.privacySettings.showRecordingIndicator:
            .systemRed
        case .error:
            .systemOrange
        default:
            nil
        }
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

    @objc private func playLastRecording() {
        guard let lastRecording = appState.lastRecording,
              FileManager.default.fileExists(atPath: lastRecording.mixedAudioURL.path(percentEncoded: false))
        else {
            return
        }

        NSWorkspace.shared.open(lastRecording.mixedAudioURL)
        AppLogger.storage.info("Played latest recording mixed preview")
    }

    @objc private func openLastRecordingFolder() {
        guard let lastRecording = appState.lastRecording else {
            openLibrary()
            return
        }

        NSWorkspace.shared.open(lastRecording.sessionFolderURL)
        AppLogger.storage.info("Opened latest recording folder")
    }

    @objc private func openLibrary() {
        AppWindows.openLibrary(appState: appState)
    }

    @objc private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    @objc private func showDiagnostics() {
        AppWindows.openDiagnostics(appState: appState)
    }

    private func showMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        let mainWindow = NSApp.windows.first { window in
            window.title == "TOrbit Recorder"
        } ?? fallbackMainWindow ?? makeFallbackMainWindow()

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
        window.title = "TOrbit Recorder"
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
        AppLogger.app.info("TOrbitRecorder quit requested")
        NSApp.terminate(nil)
    }
}
