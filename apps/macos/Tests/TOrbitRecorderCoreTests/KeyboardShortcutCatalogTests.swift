import Testing
@testable import TOrbitRecorderCore

struct KeyboardShortcutCatalogTests {
    @Test
    func exposesMVPAppActiveShortcuts() {
        let shortcuts = KeyboardShortcutCatalog.appActiveShortcuts

        #expect(shortcuts.count == 5)
        #expect(shortcuts.map(\.displayText) == [
            "Cmd+Shift+R",
            "Cmd+Shift+O",
            "Cmd+Shift+L",
            "Cmd+Shift+D",
            "Cmd+Shift+S"
        ])
        #expect(shortcuts.map(\.keyEquivalent) == ["r", "o", "l", "d", "s"])
        #expect(KeyboardShortcutCatalog.openLatestRecordingFolder.title == "Open Library")
        #expect(KeyboardShortcutCatalog.openLibrary.title == "Open Records")
    }

    @Test
    func exposesGlobalScreenshotShortcut() {
        #expect(KeyboardShortcutCatalog.captureScreenshotGlobal.title == "Capture full screenshot")
        #expect(KeyboardShortcutCatalog.captureScreenshotGlobal.keyEquivalent == "s")
        #expect(KeyboardShortcutCatalog.captureScreenshotGlobal.displayText == "Ctrl+Option+S")
    }

    @Test
    func exposesGlobalShowWindowShortcut() {
        #expect(KeyboardShortcutCatalog.showWindowGlobal.title == "Show window")
        #expect(KeyboardShortcutCatalog.showWindowGlobal.keyEquivalent == "r")
        #expect(KeyboardShortcutCatalog.showWindowGlobal.displayText == "Ctrl+Option+R")
    }

    @Test
    func keepsMarkerShortcutsOutOfDefaultHotkeyList() {
        #expect(KeyboardShortcutCatalog.markerShortcuts.map(\.displayText) == [
            "Cmd+1",
            "Cmd+2",
            "Cmd+3",
            "Cmd+4",
            "Cmd+5"
        ])
        #expect(!KeyboardShortcutCatalog.appActiveShortcuts.contains { $0.id.hasPrefix("marker_") })
    }
}
