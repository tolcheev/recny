import Testing
@testable import TOrbitRecorderCore

struct KeyboardShortcutCatalogTests {
    @Test
    func exposesMVPAppActiveShortcuts() {
        let shortcuts = KeyboardShortcutCatalog.appActiveShortcuts

        #expect(shortcuts.count == 9)
        #expect(shortcuts.map(\.displayText) == [
            "Cmd+Shift+R",
            "Cmd+Shift+O",
            "Cmd+Shift+L",
            "Cmd+Shift+D",
            "Cmd+1",
            "Cmd+2",
            "Cmd+3",
            "Cmd+4",
            "Cmd+5"
        ])
        #expect(shortcuts.map(\.keyEquivalent) == ["r", "o", "l", "d", "1", "2", "3", "4", "5"])
    }
}
