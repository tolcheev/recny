import SwiftUI
import TOrbitRecorderCore

struct TOrbitRecorderCommands: Commands {
    @ObservedObject var appState: AppState
    let appDelegate: AppDelegate

    var body: some Commands {
        CommandMenu("ToRec") {
            Button(recordingToggleTitle) {
                appDelegate.toggleRecordingFromShortcut()
            }
            .disabled(appState.isStoppingRecording)
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.toggleRecording.keyEquivalent)),
                modifiers: [.command, .shift]
            )

            Button("Open Library") {
                appDelegate.openLatestRecordingFolderFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.openLatestRecordingFolder.keyEquivalent)),
                modifiers: [.command, .shift]
            )

            Button("Open Records") {
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

            Button("Capture Full Screenshot") {
                appDelegate.captureScreenshotFromShortcut()
            }
            .keyboardShortcut(
                KeyEquivalent(Character(KeyboardShortcutCatalog.captureScreenshot.keyEquivalent)),
                modifiers: [.command, .shift]
            )
        }

        CommandGroup(replacing: .appSettings) {
            Button("Settings...") {
                appDelegate.openSettingsFromShortcut()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
    }

    private var recordingToggleTitle: String {
        if appState.isStoppingRecording {
            return "Stopping..."
        }

        return appState.status == .recording ? "Stop Recording" : "Start Recording"
    }
}
