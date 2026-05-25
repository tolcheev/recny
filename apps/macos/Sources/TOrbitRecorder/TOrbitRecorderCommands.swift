import SwiftUI
import TOrbitRecorderCore

struct TOrbitRecorderCommands: Commands {
    @ObservedObject var appState: AppState
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandMenu("T-Orbit Recorder") {
            Button(appState.status == .recording ? "Stop Recording" : "Start Recording") {
                appDelegate.toggleRecordingFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.toggleRecording.keyEquivalent)),
                modifiers: [.command, .shift]
            )

            Button("Open Recordings Folder") {
                appDelegate.openLatestRecordingFolderFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.openLatestRecordingFolder.keyEquivalent)),
                modifiers: [.command, .shift]
            )

            Button("Open Library") {
                appDelegate.openLibraryFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.openLibrary.keyEquivalent)),
                modifiers: [.command, .shift]
            )

            Button("Open Diagnostics") {
                appDelegate.openDiagnosticsFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.openDiagnostics.keyEquivalent)),
                modifiers: [.command, .shift]
            )
        }
    }
}
