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
    }
}
