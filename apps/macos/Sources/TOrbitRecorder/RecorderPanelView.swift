import AppKit
import SwiftUI
import TOrbitRecorderCore

struct RecorderPanelView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            recordingBlock
            lastRecordingBlock
            footerActions
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 560)
        .sheet(isPresented: $appState.isPostCallPanelPresented) {
            if let draft = appState.postCallDraft {
                PostCallTaggingView(draft: draft) { updatedDraft in
                    try appState.savePostCallDraft(updatedDraft)
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .center) {
            Text("TOrbit Recorder")
                .font(.title2.weight(.semibold))

            Spacer()

            StatusPill(text: statusLabel, color: statusColor)
        }
    }

    private var recordingBlock: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 16) {
                Text(appState.formattedDuration)
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)

                Button {
                    Task {
                        do {
                            if appState.status == .recording {
                                try await appState.stopRecording()
                            } else {
                                try await appState.startRecording()
                            }
                        } catch {
                            AppLogger.recording.error("Main recording button failed: \(String(describing: error), privacy: .public)")
                        }
                    }
                } label: {
                    Label(
                        appState.status == .recording ? "Stop Recording" : "Start Recording",
                        systemImage: appState.status == .recording ? "stop.fill" : "record.circle"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.status == .recording ? .red : .accentColor)
                .disabled(appState.status == .error)

                VStack(alignment: .leading, spacing: 8) {
                    DetailLine(label: "Mic", value: appState.selectedMicrophoneName)
                    DetailLine(label: "System audio", value: systemAudioLabel)
                    DetailLine(label: "Auto-start", value: appState.autoStartSettings.isEnabled ? "On" : "Off")
                }

                if let warning = appState.microphoneInputWarning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .textSelection(.enabled)
                }

                if appState.status == .error {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Text("Recording failed. Open diagnostics.")
                            .font(.callout)
                            .foregroundStyle(.red)
                        Spacer()
                        Button("Diagnostics") {
                            AppWindows.openDiagnostics(appState: appState)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } label: {
            Text("Recording")
                .font(.headline)
        }
    }

    private var lastRecordingBlock: some View {
        GroupBox {
            if let recording = appState.lastRecording {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(recording.displayStatus)
                                .font(.headline)
                                .foregroundStyle(lastRecordingColor(recording.status))

                            if recording.status == .shortRecording {
                                Text("Saved to Inbox/Short")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            } else if recording.status == .failed {
                                Text("Recording failed. Open diagnostics.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Spacer()
                    }

                    Text(recording.title)
                        .font(.callout.weight(.medium))
                        .lineLimit(1)

                    HStack(spacing: 18) {
                        DetailLine(label: "Duration", value: formatDuration(recording.durationSec))
                        DetailLine(label: "Audio", value: audioSummary(for: recording))
                    }

                    HStack(spacing: 10) {
                        Button {
                            playMixed(recording)
                        } label: {
                            Label("Play", systemImage: "play.fill")
                        }
                        .disabled(recording.mixedPreviewState != "Ready")

                        Button {
                            NSWorkspace.shared.open(recording.sessionFolderURL)
                        } label: {
                            Label("Open Folder", systemImage: "folder")
                        }

                        Button {
                            appState.editLastRecordingTags()
                        } label: {
                            Label("Tag", systemImage: "tag")
                        }
                    }
                }
            } else {
                Text("No recordings yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Text("Last Recording")
                .font(.headline)
        }
    }

    private var footerActions: some View {
        HStack(spacing: 12) {
            Button {
                AppWindows.openLibrary(appState: appState)
            } label: {
                Label("Library", systemImage: "tray.full")
            }

            Button {
                showSettings()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }

            Spacer()

            Button("Diagnostics") {
                AppWindows.openDiagnostics(appState: appState)
            }
            .buttonStyle(.link)
        }
    }

    private var statusLabel: String {
        switch appState.status {
        case .idle:
            return "Idle"
        case .recording:
            return "Recording"
        case .error:
            return "Error"
        }
    }

    private var statusColor: Color {
        switch appState.status {
        case .idle:
            return .secondary
        case .recording:
            return .red
        case .error:
            return .orange
        }
    }

    private var systemAudioLabel: String {
        guard appState.recordingSettings.systemAudioEnabled else {
            return "Off"
        }

        switch appState.systemAudioStatus {
        case .recording:
            return "Active"
        case .permissionDenied:
            return "Missing permission"
        case .error:
            return "Error"
        default:
            return appState.status == .recording ? "Active" : "Ready"
        }
    }

    private func lastRecordingColor(_ status: TaggingStatus) -> Color {
        switch status {
        case .failed:
            return .red
        case .shortRecording:
            return .orange
        default:
            return .green
        }
    }

    private func audioSummary(for recording: LastRecordingSummary) -> String {
        let hasMic = (recording.micFileSizeBytes ?? 0) > 0
        let hasSystem = (recording.systemFileSizeBytes ?? 0) > 0

        switch (hasMic, hasSystem) {
        case (true, true):
            return "mic + system"
        case (true, false):
            return "mic only"
        case (false, true):
            return "system only"
        case (false, false):
            return "missing"
        }
    }

    private func playMixed(_ recording: LastRecordingSummary) {
        guard recording.mixedPreviewState == "Ready" else {
            return
        }

        NSWorkspace.shared.open(recording.mixedAudioURL)
    }

    private func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            return String(format: "%d:%02d:%02d", hours, remainingMinutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

private struct DetailLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Text("\(label):")
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(text)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(.quaternary.opacity(0.45), in: Capsule())
    }
}
