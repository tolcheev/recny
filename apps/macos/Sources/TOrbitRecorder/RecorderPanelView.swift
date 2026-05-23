import SwiftUI
import TOrbitRecorderCore

struct RecorderPanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                StatusRow(label: "Status", value: appState.status.rawValue)
                StatusRow(label: "Duration", value: appState.formattedDuration)
                StatusRow(label: "Mic", value: appState.micStatus.rawValue)
                StatusRow(label: "System Audio", value: appState.systemAudioStatus.rawValue)
                StatusRow(label: "Output Folder", value: appState.outputFolderPath)
            }

            if let errorMessage = appState.errorMessage {
                Text(errorMessage)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            HStack(spacing: 10) {
                Button("Start") {
                    Task {
                        try? await appState.startRecording()
                    }
                }
                .disabled(appState.status == .recording)

                Button("Stop") {
                    Task {
                        try? await appState.stopRecording()
                    }
                }
                .disabled(appState.status != .recording)

                Button("Open Folder") {
                    openOutputFolder()
                }
            }
        }
        .frame(minWidth: 460, minHeight: 260)
        .padding(24)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: appState.status == .recording ? "record.circle.fill" : "record.circle")
                .font(.title2)
                .foregroundStyle(appState.status == .recording ? .red : .secondary)

            Text("TOrbitRecorder")
                .font(.title2.weight(.semibold))
        }
    }

    private func openOutputFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
        } catch {
            AppLogger.storage.error("Failed to open output folder from panel: \(String(describing: error), privacy: .public)")
        }
    }
}

private struct StatusRow: View {
    let label: String
    let value: String

    var body: some View {
        GridRow {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Text(value)
                .font(.callout.monospacedDigit())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
