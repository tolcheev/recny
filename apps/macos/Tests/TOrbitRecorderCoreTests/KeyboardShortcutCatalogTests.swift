import Testing
@testable import TOrbitRecorderCore

struct KeyboardShortcutCatalogTests {
    @Test
    func exposesMVPAppActiveShortcuts() {
        let shortcuts = KeyboardShortcutCatalog.appActiveShortcuts

        #expect(shortcuts.count == 4)
        #expect(shortcuts.map(\.displayText) == [
            "Cmd+Shift+R",
            "Cmd+Shift+O",
            "Cmd+Shift+L",
            "Cmd+Shift+D"
        ])
        #expect(shortcuts.map(\.keyEquivalent) == ["r", "o", "l", "d"])
        #expect(KeyboardShortcutCatalog.openLatestRecordingFolder.title == "Open Library")
        #expect(KeyboardShortcutCatalog.openLibrary.title == "Open Records")
    }

    @Test
    func showWindowGlobalShortcutIsDisabledToAvoidAppConflicts() {
        #expect(KeyboardShortcutCatalog.showWindowGlobal.keyEquivalent.isEmpty)
        #expect(KeyboardShortcutCatalog.showWindowGlobal.displayText == "Menu bar")
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
