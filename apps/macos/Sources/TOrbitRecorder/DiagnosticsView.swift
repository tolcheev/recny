import AppKit
import AVFoundation
import CoreGraphics
import SwiftUI
import TOrbitRecorderCore

struct DiagnosticsView: View {
    @ObservedObject var appState: AppState

    @State private var clearResult: String?
    @State private var testResult: String?
    @State private var isRunningTestRecording = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                permissionsSection
                errorSection
                recoverableSection
                logsSection
                testRecordingSection
            }
            .padding(20)
        }
        .frame(minWidth: 700, minHeight: 560)
        .onAppear {
            try? appState.reloadRecoverableRecordings()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Diagnostics")
                .font(.title2.weight(.semibold))
            Text("Permissions, recovery, logs, and a local test recording action.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionsSection: some View {
        GroupBox("Permissions") {
            VStack(alignment: .leading, spacing: 8) {
                DiagnosticLine(label: "Microphone", value: microphonePermission)
                DiagnosticLine(label: "Screen & System Audio Recording", value: screenCapturePermission)
                DiagnosticLine(label: "Selected mic", value: appState.selectedMicrophoneName)

                if let warning = appState.microphoneInputWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var errorSection: some View {
        GroupBox("Last Error") {
            Text(appState.errorMessage ?? "None")
                .font(.callout.monospaced())
                .foregroundStyle(appState.errorMessage == nil ? Color.secondary : Color.red)
                .textSelection(.enabled)
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
                Text("Runs a short local recording with the same pipeline as the main Start button.")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                Button {
                    runTestRecording()
                } label: {
                    Label("Run test recording", systemImage: "waveform")
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

    private var microphonePermission: String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return "Authorized"
        case .notDetermined:
            return "Not determined"
        case .denied:
            return "Denied"
        case .restricted:
            return "Restricted"
        @unknown default:
            return "Unknown"
        }
    }

    private var screenCapturePermission: String {
        CGPreflightScreenCaptureAccess() ? "Authorized" : "Missing permission"
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
        testResult = "Running 5 second test recording..."

        Task {
            do {
                try await appState.startRecording()
                try await Task.sleep(for: .seconds(5))
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
