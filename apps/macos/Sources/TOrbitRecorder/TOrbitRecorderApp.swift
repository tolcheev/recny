import SwiftUI

@main
struct TOrbitRecorderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("T-Orbit Recorder", id: "main") {
            MainRecorderView(appState: appDelegate.appState)
        }
        .commands {
            TOrbitRecorderCommands(appState: appDelegate.appState, appDelegate: appDelegate)
        }
    }
}
