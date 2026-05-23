import AppKit
import Foundation
import SwiftUI
import TOrbitRecorderCore

struct DiagnosticsView: View {
    @ObservedObject var appState: AppState

    @State private var clearResult: String?
    @State private var testResult: String?
    @State private var isRunningTestRecording = false
    @State private var showRawError = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionsSection
                deviceSection
                errorSection
                recoverableSection
                logsSection
                testRecordingSection
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            appState.refreshPermissionSnapshot()
            try? appState.reloadRecoverableRecordings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Diagnostics")
                .font(.title2.weight(.semibold))
            Text("Permissions, devices, recovery, logs, and test recording.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 10) {
                PermissionChecklistContent(appState: appState)

                HStack {
                    Spacer()

                    Button {
                        appState.refreshPermissionSnapshot()
                    } label: {
                        Label("Recheck", systemImage: "arrow.clockwise")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var deviceSection: some View {
        GroupBox("Device Diagnostics") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    DiagnosticLine(
                        label: "Selected input",
                        value: RecordingDisplayFormatter.microphoneName(appState.selectedMicrophoneName)
                    )

                    Spacer()

                    Button {
                        appState.refreshMicrophoneDevices()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if let warning = appState.microphoneInputWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Available input devices")
                        .font(.callout.weight(.medium))

                    if appState.availableMicrophoneDevices.isEmpty {
                        Text("No input devices detected.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.availableMicrophoneDevices) { device in
                            Text(device.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorSection: some View {
        GroupBox("Last Error") {
            VStack(alignment: .leading, spacing: 8) {
                if let errorMessage = appState.errorMessage {
                    Text(RecordingDisplayFormatter.humanReadableError(errorMessage))
                        .font(.callout.weight(.medium))
                        .foregroundStyle(.red)

                    Button(showRawError ? "Hide raw error" : "Show raw error") {
                        showRawError.toggle()
                    }
                    .buttonStyle(.link)

                    if showRawError {
                        Text(errorMessage)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("None")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recoverableSection: some View {
        GroupBox("Recoverable Recordings") {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Interrupted sessions with usable audio files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        do {
                            let removed = try appState.clearEmptyRecoverableRecordings()
                            clearResult = "Removed \(removed) empty recoverable folders."
                        } catch {
                            clearResult = String(describing: error)
                        }
                    } label: {
                        Label("Clear empty recoverables", systemImage: "trash")
                    }

                    Button {
                        try? appState.reloadRecoverableRecordings()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }

                if appState.recoverableRecordings.isEmpty {
                    Text("No recoverable recordings with usable files.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(appState.recoverableRecordings) { recording in
                            RecoverableRecordingRow(recording: recording, appState: appState)
                        }
                    }
                }

                if let clearResult {
                    Text(clearResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsSection: some View {
        GroupBox("Logs") {
            HStack(spacing: 10) {
                Text(logsURL.path(percentEncoded: false))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                Spacer()

                Button {
                    openLogs()
                } label: {
                    Label("Open Logs", systemImage: "folder")
                }
            }
        }
    }

    private var testRecordingSection: some View {
        GroupBox("Test Recording") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Runs a 10 second local recording with the same pipeline as the main Start button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    runTestRecording()
                } label: {
                    Label("Run 10 sec test recording", systemImage: "waveform")
                }
                .disabled(appState.status == .recording || isRunningTestRecording)

                if let testResult {
                    Text(testResult)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var logsURL: URL {
        appState.outputFolderURL.appendingPathComponent("logs", isDirectory: true)
    }

    private func openLogs() {
        do {
            try FileManager.default.createDirectory(
                at: logsURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(logsURL)
        } catch {
            AppLogger.storage.error("Failed to open logs folder: \(String(describing: error), privacy: .public)")
        }
    }

    private func runTestRecording() {
        isRunningTestRecording = true
        testResult = "Running 10 second test recording..."

        Task {
            do {
                try await appState.startRecording()
                try await Task.sleep(for: .seconds(10))
                try await appState.stopRecording()
                testResult = "Test recording stopped. Check Last Recording and Library."
            } catch {
                testResult = String(describing: error)
            }

            isRunningTestRecording = false
        }
    }
}

private struct DiagnosticLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 8) {
            Text("\(label):")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
            Spacer()
        }
    }
}

private struct RecoverableRecordingRow: View {
    let recording: RecoverableRecordingSummary
    let appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(recording.id)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)

                Spacer()

                Text("Recoverable")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.orange)
            }

            HStack(spacing: 8) {
                Text("\(recording.segmentCount) segments")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text("\(recording.recoverableFileCount) files")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(recording.startedAt)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            HStack(spacing: 8) {
                Button("Recover Recording") {
                    Task {
                        try? await appState.recoverRecording(recording)
                    }
                }

                Button("Open Folder") {
                    NSWorkspace.shared.open(recording.folderURL)
                }
            }
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}
