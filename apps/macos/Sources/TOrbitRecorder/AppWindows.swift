import AppKit
import SwiftUI
import TOrbitRecorderCore

@MainActor
enum AppWindows {
    private static var libraryWindow: NSWindow?
    private static var diagnosticsWindow: NSWindow?
    private static var settingsWindow: NSWindow?
    private static var audioPlayerWindow: NSWindow?
    private static var audioPlayerURL: URL?

    static func openLibrary(appState: AppState) {
        let window = libraryWindow ?? makeWindow(
            title: "ToRec Records",
            width: 1_280,
            height: 760,
            rootView: LibraryView(appState: appState)
        )
        libraryWindow = window
        present(window)
    }

    static func openDiagnostics(appState: AppState) {
        let window = diagnosticsWindow ?? makeWindow(
            title: "ToRec Diagnostics",
            width: 760,
            height: 620,
            rootView: DiagnosticsView(appState: appState)
        )
        diagnosticsWindow = window
        present(window)
    }

    static func openSettings(appState: AppState) {
        let window = settingsWindow ?? makeWindow(
            title: "ToRec Settings",
            width: 700,
            height: 720,
            rootView: SettingsView(appState: appState)
        )
        settingsWindow = window
        present(window)
    }

    static func openAudioPlayer(url: URL, title: String) {
        audioPlayerWindow?.close()
        let window = makeWindow(
            title: "ToRec Player",
            width: 520,
            height: 180,
            rootView: AudioPlayerView(url: url, title: title)
        )
        audioPlayerWindow = window
        audioPlayerURL = url
        AppLogger.file(.info, category: "playback", "open in-app player path=\(url.path(percentEncoded: false))")
        present(window)
    }

    static func closeAudioPlayer() {
        audioPlayerWindow?.close()
        audioPlayerWindow = nil
        audioPlayerURL = nil
    }

    @discardableResult
    static func closeAudioPlayer(ifPlayingInside sessionFolderURL: URL) -> Bool {
        guard RecordingPlaybackResolver.isPlaybackURL(audioPlayerURL, insideSessionFolder: sessionFolderURL) else {
            return false
        }

        closeAudioPlayer()
        return true
    }

    static func openRecordingsFolder(appState: AppState) {
        let recordingsURL = StoragePathBuilder(rootURL: appState.outputFolderURL).libraryURL
        do {
            try FileManager.default.createDirectory(
                at: recordingsURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(recordingsURL)
        } catch {
            AppLogger.file(.error, category: "storage", "open recordings folder failed path=\(recordingsURL.path(percentEncoded: false)) error=\(String(describing: error))")
        }
    }

    private static func makeWindow<Content: View>(
        title: String,
        width: CGFloat,
        height: CGFloat,
        rootView: Content
    ) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentViewController = NSHostingController(rootView: rootView)
        window.isReleasedWhenClosed = false
        return window
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        AppWindowCentering.centerAfterPresentation(window)
    }
}
