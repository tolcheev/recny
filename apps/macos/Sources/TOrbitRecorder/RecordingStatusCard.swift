import SwiftUI
import TOrbitRecorderCore

struct RecordingStatusCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .center, spacing: 18) {
            switch appState.status {
            case .idle:
                idleContent
            case .recording:
                recordingContent
            case .error:
                errorContent
            }
        }
        .padding(.vertical, 22)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
    }

    private var idleContent: some View {
        VStack(alignment: .center, spacing: 16) {
            if appState.isRecordingStartAllowed {
                PrimaryRecordingButton(status: appState.status) {
                    startRecording()
                }
            } else {
                VStack(spacing: 6) {
                    Label("Permissions needed", systemImage: "lock.shield")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    Text(appState.recordingStartBlockingReason ?? "Fix permissions before recording.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    AppWindows.openDiagnostics(appState: appState)
                } label: {
                    Label("Fix Permissions", systemImage: "lock.shield")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .accessibilityLabel("Fix Permissions")
            }

            idleSummary
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .center, spacing: 16) {
            Text(appState.formattedDuration)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Current recording duration \(appState.formattedDuration)")

            PrimaryRecordingButton(status: appState.status) {
                stopRecording()
            }

            VStack(spacing: 5) {
                Text("Recording mic + system audio")
                    .font(.callout.weight(.medium))

                Label("All system audio is being recorded", systemImage: "speaker.wave.2")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("All system audio is being recorded")
            }
        }
    }

    private var errorContent: some View {
        VStack(alignment: .center, spacing: 14) {
            VStack(spacing: 7) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title2)
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)

                Text("Recording failed")
                    .font(.title3.weight(.semibold))

                Text(RecordingDisplayFormatter.humanReadableError(appState.errorMessage))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 10) {
                Button {
                    AppWindows.openDiagnostics(appState: appState)
                } label: {
                    Label("Open Diagnostics", systemImage: "stethoscope")
                }
                .accessibilityLabel("Open Diagnostics")

                Button {
                    startRecording()
                } label: {
                    Label("Try Again", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Try Again")
            }
        }
    }

    private var idleSummary: some View {
        VStack(spacing: 6) {
            summaryText(label: "Mic", value: RecordingDisplayFormatter.microphoneName(appState.selectedMicrophoneName))
            summaryText(
                label: "System audio",
                value: RecordingDisplayFormatter.systemAudioText(
                    isEnabled: appState.recordingSettings.systemAudioEnabled,
                    captureStatus: appState.systemAudioStatus,
                    recordingStatus: appState.status
                )
            )
            summaryText(label: "Auto-start", value: appState.autoStartSettings.isEnabled ? "On" : "Off")

            if let warning = appState.microphoneInputWarning {
                Label(
                    warning,
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel(warning)
            }
        }
    }

    private func summaryText(label: String, value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text("\(label):")
                .fontWeight(.medium)
            Text(value)
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .truncationMode(.middle)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label), \(value)")
    }

    private func startRecording() {
        Task {
            do {
                try await appState.startRecording()
            } catch {
                AppLogger.recording.error("Start recording from main window failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func stopRecording() {
        Task {
            do {
                try await appState.stopRecording()
            } catch {
                AppLogger.recording.error("Stop recording from main window failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
