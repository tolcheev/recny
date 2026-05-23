import SwiftUI

@main
struct TOrbitRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("TOrbit Recorder", id: "main") {
            MainRecorderView(appState: appDelegate.appState)
        }

        Settings {
            SettingsView(appState: appDelegate.appState)
        }
    }
}
