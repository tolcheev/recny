import Foundation

public struct KeyboardShortcutDefinition: Equatable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let keyEquivalent: String
    public let displayText: String

    public init(
        id: String,
        title: String,
        keyEquivalent: String,
        displayText: String
    ) {
        self.id = id
        self.title = title
        self.keyEquivalent = keyEquivalent
        self.displayText = displayText
    }
}

public enum KeyboardShortcutCatalog {
    public static let toggleRecording = KeyboardShortcutDefinition(
        id: "toggle_recording",
        title: "Start/Stop recording",
        keyEquivalent: "r",
        displayText: "Cmd+Shift+R"
    )

    public static let openLatestRecordingFolder = KeyboardShortcutDefinition(
        id: "open_latest_recording_folder",
        title: "Open latest recording folder",
        keyEquivalent: "o",
        displayText: "Cmd+Shift+O"
    )

    public static let openLibrary = KeyboardShortcutDefinition(
        id: "open_library",
        title: "Open Library",
        keyEquivalent: "l",
        displayText: "Cmd+Shift+L"
    )

    public static let openDiagnostics = KeyboardShortcutDefinition(
        id: "open_diagnostics",
        title: "Open Diagnostics",
        keyEquivalent: "d",
        displayText: "Cmd+Shift+D"
    )

    public static let appActiveShortcuts: [KeyboardShortcutDefinition] = [
        toggleRecording,
        openLatestRecordingFolder,
        openLibrary,
        openDiagnostics
    ]
}
