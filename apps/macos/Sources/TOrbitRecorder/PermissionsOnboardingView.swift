import SwiftUI
import TOrbitRecorderCore

struct PermissionsOnboardingView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        RecorderCard {
            onboardingHeader

            PermissionChecklistContent(appState: appState)
        }
    }

    private var onboardingHeader: some View {
        let isBlocked = appState.recordingStartBlockingReason != nil || !appState.isRecordingStartAllowed
        let toneColor = isBlocked ? Color.red : Color.green

        return VStack(alignment: .leading, spacing: 7) {
            Label(
                isBlocked ? "Recording is blocked" : "Recording permissions ready",
                systemImage: isBlocked ? "exclamationmark.octagon.fill" : "checkmark.shield.fill"
            )
                .font(.headline)
                .foregroundStyle(toneColor)

            Text(isBlocked
                 ? "ToRec needs local access before Start Recording is available."
                 : "ToRec has the local access required for recording.")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let blockingReason = appState.recordingStartBlockingReason {
                Text(blockingReason)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(toneColor)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(toneColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(toneColor.opacity(0.55), lineWidth: 1.5)
        )
    }
}

struct PermissionChecklistContent: View {
    @ObservedObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionStatusRow(
                title: PermissionOnboardingFormatter.title(for: .microphone),
                state: appState.permissionSnapshot.microphone,
                explanation: PermissionOnboardingFormatter.explanation(
                    for: .microphone,
                    state: appState.permissionSnapshot.microphone
                ),
                actionTitle: PermissionOnboardingFormatter.inlineActionTitle(
                    for: .microphone,
                    state: appState.permissionSnapshot.microphone
                ),
                actionSystemImage: "mic"
            ) {
                PermissionActionHandler.handleMicrophoneAction(appState: appState)
            }

            PermissionStatusRow(
                title: PermissionOnboardingFormatter.title(for: .screenSystemAudio),
                state: appState.permissionSnapshot.screenSystemAudio,
                explanation: PermissionOnboardingFormatter.explanation(
                    for: .screenSystemAudio,
                    state: appState.permissionSnapshot.screenSystemAudio
                ),
                actionTitle: PermissionOnboardingFormatter.inlineActionTitle(
                    for: .screenSystemAudio,
                    state: appState.permissionSnapshot.screenSystemAudio
                ),
                actionSystemImage: "speaker.wave.2"
            ) {
                PermissionActionHandler.handleSystemAudioAction(appState: appState)
            }

            PermissionStatusRow(
                title: PermissionOnboardingFormatter.title(for: .storage),
                state: appState.permissionSnapshot.storage,
                explanation: PermissionOnboardingFormatter.explanation(
                    for: .storage,
                    state: appState.permissionSnapshot.storage
                ),
                actionTitle: PermissionOnboardingFormatter.inlineActionTitle(
                    for: .storage,
                    state: appState.permissionSnapshot.storage
                ),
                actionSystemImage: "folder"
            ) {
                PermissionActionHandler.openRecordingsFolder(appState: appState)
            }

            if let message = appState.permissionOnboardingMessage {
                PermissionOnboardingFeedback(
                    message: message,
                    isRunning: appState.isPermissionOnboardingInProgress
                )
            }

            if requiresRestart {
                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(
                        PermissionOnboardingFormatter.restartMessage,
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)

                    Spacer()

                    Button("Quit App") {
                        NSApp.terminate(nil)
                    }

                    Button("Restart App") {
                        PermissionActionHandler.restartApp()
                    }
                }

                Text(PermissionOnboardingFormatter.reopenInstruction(bundlePath: Bundle.main.bundleURL.path(percentEncoded: false)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var requiresRestart: Bool {
        PermissionOnboardingFormatter.requiresRestart(appState.permissionSnapshot)
    }
}

private struct PermissionOnboardingFeedback: View {
    let message: String
    let isRunning: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if isRunning {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Checking permissions")
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .accessibilityHidden(true)
            }

            Text(message)
                .font(.caption.weight(.medium))
                .foregroundStyle(isRunning ? Color.secondary : Color.green)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let state: RecorderPermissionState
    let explanation: String
    let actionTitle: String?
    let actionSystemImage: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .font(.title3)
                .foregroundStyle(tone.color)
                .frame(width: 24)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.callout.weight(.semibold))

                    StatusBadge(text: state.title, tone: tone)
                }

                Text(explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            if let actionTitle {
                Button {
                    action()
                } label: {
                    Label(actionTitle, systemImage: actionSystemImage)
                        .font(.caption)
                        .lineLimit(1)
                }
                .controlSize(.small)
                .help(actionTitle)
                .accessibilityLabel(actionTitle)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var tone: StatusTone {
        switch state {
        case .granted:
            return .ready
        case .denied:
            return .danger
        case .restartRequired, .missing, .notDetermined:
            return .warning
        case .unknown:
            return .neutral
        }
    }

    private var iconName: String {
        switch state {
        case .granted:
            return "checkmark.circle.fill"
        case .denied:
            return "xmark.octagon.fill"
        case .restartRequired:
            return "arrow.clockwise.circle.fill"
        case .missing, .notDetermined:
            return "exclamationmark.triangle.fill"
        case .unknown:
            return "questionmark.circle.fill"
        }
    }
}
