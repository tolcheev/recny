import SwiftUI
import TOrbitRecorderCore

struct RecordingStatusCard: View {
    @ObservedObject var appState: AppState

    var body: some View {
        RecorderCard {
            switch appState.status {
            case .idle:
                idleContent
            case .recording:
                recordingContent
            case .error:
                errorContent
            }
        }
    }

    private var idleContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader(title: "Ready", subtitle: "Ready to record microphone and system audio.", tone: .ready)

            PrimaryRecordingButton(status: appState.status) {
                startRecording()
            }

            captureRows
        }
    }

    private var recordingContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader(title: "Recording", subtitle: "Recording microphone and system audio.", tone: .recording)

            Text(appState.formattedDuration)
                .font(.system(size: 56, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Current recording duration \(appState.formattedDuration)")

            PrimaryRecordingButton(status: appState.status) {
                stopRecording()
            }

            captureRows

            Label("All system audio is being recorded", systemImage: "speaker.wave.2")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("All system audio is being recorded")
        }
    }

    private var errorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            statusHeader(
                title: "Recording failed",
                subtitle: RecordingDisplayFormatter.humanReadableError(appState.errorMessage),
                tone: .danger
            )

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

    private var captureRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            InfoRow(
                label: "Mic",
                value: RecordingDisplayFormatter.microphoneName(appState.selectedMicrophoneName)
            )
            InfoRow(
                label: "System audio",
                value: RecordingDisplayFormatter.systemAudioText(
                    isEnabled: appState.recordingSettings.systemAudioEnabled,
                    captureStatus: appState.systemAudioStatus,
                    recordingStatus: appState.status
                )
            )
            InfoRow(
                label: "Auto-start",
                value: appState.autoStartSettings.isEnabled ? "On" : "Off"
            )

            if let warning = appState.microphoneInputWarning {
                Label(
                    "Bluetooth headset microphone is available, but built-in or external microphone is preferred for better quality.",
                    systemImage: "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityLabel(warning)
            }
        }
    }

    private func statusHeader(title: String, subtitle: String, tone: StatusTone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: tone))
                .font(.title2)
                .foregroundStyle(tone.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))

                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
    }

    private func iconName(for tone: StatusTone) -> String {
        switch tone {
        case .ready:
            return "checkmark.circle.fill"
        case .recording:
            return "record.circle.fill"
        case .danger:
            return "exclamationmark.triangle.fill"
        default:
            return "circle.fill"
        }
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
