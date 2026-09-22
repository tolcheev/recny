import SwiftUI

@main
struct RecnyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Recny", id: "main") {
            MainRecorderView(appState: appDelegate.appState)
        }
        .commands {
            RecnyCommands(appState: appDelegate.appState, appDelegate: appDelegate)
        }
    }
}
