import SwiftUI

@main
struct TOrbitRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TOrbitRecorder", id: "main") {
            RecorderPanelView(appState: appDelegate.appState)
        }

        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}
