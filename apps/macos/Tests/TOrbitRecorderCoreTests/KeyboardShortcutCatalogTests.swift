import Testing
@testable import TOrbitRecorderCore

struct KeyboardShortcutCatalogTests {
    @Test
    func exposesMVPAppActiveShortcuts() {
        let shortcuts = KeyboardShortcutCatalog.appActiveShortcuts

        #expect(shortcuts.count == 5)
        #expect(shortcuts.map(\.displayText) == [
            "Ctrl+Option+Cmd+R",
            "Cmd+Shift+R",
            "Cmd+Shift+O",
            "Cmd+Shift+L",
            "Cmd+Shift+D"
        ])
        #expect(shortcuts.map(\.keyEquivalent) == ["r", "r", "o", "l", "d"])
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
