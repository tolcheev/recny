import Testing
@testable import RecnyCore

struct MenuBarStatusItemPlacementTests {
    @Test func exposesStableAutosaveNameAndPreferredPosition() {
        #expect(MenuBarStatusItemPlacement.autosaveName == "com.torbit.recorder.status-item.v2")
        #expect(MenuBarStatusItemPlacement.preferredPositionKey == "NSStatusItem Preferred Position com.torbit.recorder.status-item.v2")
        #expect(MenuBarStatusItemPlacement.defaultPreferredPosition == 200)
    }
}
