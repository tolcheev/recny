import AppKit
import SwiftUI
import TOrbitRecorderCore

@MainActor
enum AppWindows {
    private static var libraryWindow: NSWindow?
    private static var diagnosticsWindow: NSWindow?

    static func openLibrary(appState: AppState) {
        let window = libraryWindow ?? makeWindow(
            title: "TOrbit Recorder Library",
            width: 860,
            height: 640,
            rootView: LibraryView(appState: appState)
        )
        libraryWindow = window
        present(window)
    }

    static func openDiagnostics(appState: AppState) {
        let window = diagnosticsWindow ?? makeWindow(
            title: "TOrbit Recorder Diagnostics",
            width: 760,
            height: 620,
            rootView: DiagnosticsView(appState: appState)
        )
        diagnosticsWindow = window
        present(window)
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
        window.center()
        return window
    }

    private static func present(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
