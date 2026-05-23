import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        Form {
            Text("Output folder")
                .font(.headline)

            Text(appState.outputFolderPath)
                .textSelection(.enabled)
        }
        .padding(20)
        .frame(width: 420)
    }
}
