import AppKit
import AVFoundation
import SwiftUI
import TOrbitRecorderCore

struct PermissionsOnboardingView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        RecorderCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Set up recording permissions")
                    .font(.headline)
                Text("TOrbitRecorder needs local access before Start Recording is available.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            PermissionChecklistContent(appState: appState)
        }
    }
}

struct PermissionChecklistContent: View {
    @ObservedObject var appState: AppState
    @State private var showsReopenInstruction = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            PermissionStatusRow(
                title: "Microphone access",
                state: appState.permissionSnapshot.microphone,
                explanation: microphoneExplanation,
                actionTitle: microphoneActionTitle,
                actionSystemImage: "mic"
            ) {
                handleMicrophoneAction()
            }

            PermissionStatusRow(
                title: "Screen & System Audio Recording access",
                state: appState.permissionSnapshot.screenSystemAudio,
                explanation: screenSystemAudioExplanation,
                actionTitle: "Open Screen & System Audio Recording Settings",
                actionSystemImage: "speaker.wave.2"
            ) {
                appState.markScreenSystemAudioSettingsOpened()
                openScreenSystemAudioSettings()
            }

            PermissionStatusRow(
                title: "Storage access",
                state: appState.permissionSnapshot.storage,
                explanation: "Recordings stay local. The recordings folder must exist and be writable.",
                actionTitle: "Open Recordings Folder",
                actionSystemImage: "folder"
            ) {
                openRecordingsFolder()
            }

            if requiresRestart {
                Divider()

                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Label(
                        "Permission is enabled. Restart TOrbitRecorder to apply it.",
                        systemImage: "arrow.clockwise.circle"
                    )
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.orange)

                    Spacer()

                    Button("Quit App") {
                        NSApp.terminate(nil)
                    }

                    Button("Reopen Instruction") {
                        showsReopenInstruction.toggle()
                    }
                }

                if showsReopenInstruction {
                    Text("After quitting, reopen the same app bundle you approved in System Settings: `dist/TOrbitRecorder.app` or `/Applications/TOrbitRecorder.app`. Switching bundle paths can require permission again.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var requiresRestart: Bool {
        appState.permissionSnapshot.microphone == .restartRequired
            || appState.permissionSnapshot.screenSystemAudio == .restartRequired
            || appState.permissionSnapshot.storage == .restartRequired
    }

    private var microphoneExplanation: String {
        switch appState.permissionSnapshot.microphone {
        case .granted:
            return "Microphone recording is available."
        case .notDetermined:
            return "macOS has not granted microphone access yet."
        case .denied:
            return "Microphone access is denied. Enable it in System Settings."
        case .restartRequired:
            return "Microphone permission changed. Restart the app if macOS still blocks access."
        case .missing:
            return "Microphone access is required for source/mic.m4a."
        case .unknown:
            return "TOrbitRecorder cannot determine microphone permission."
        }
    }

    private var microphoneActionTitle: String {
        appState.permissionSnapshot.microphone == .notDetermined
            ? "Request Microphone Access"
            : "Open Microphone Settings"
    }

    private var screenSystemAudioExplanation: String {
        switch appState.permissionSnapshot.screenSystemAudio {
        case .granted:
            return "System audio recording is available."
        case .restartRequired:
            return "Permission is enabled. Restart TOrbitRecorder to apply it."
        case .denied:
            return "System audio access is denied. Enable it in System Settings, then restart the app."
        case .missing:
            return "Required for source/system.m4a and mixed preview."
        case .notDetermined:
            return "macOS has not granted Screen & System Audio Recording access yet."
        case .unknown:
            return "TOrbitRecorder cannot determine system audio permission."
        }
    }

    private func handleMicrophoneAction() {
        guard appState.permissionSnapshot.microphone == .notDetermined else {
            openMicrophoneSettings()
            return
        }

        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                appState.refreshPermissionSnapshot()
                if appState.permissionSnapshot.microphone != .granted {
                    openMicrophoneSettings()
                }
            }
        }
    }

    private func openMicrophoneSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        appState.refreshPermissionSnapshot()
    }

    private func openScreenSystemAudioSettings() {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    private func openRecordingsFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
            appState.refreshPermissionSnapshot()
        } catch {
            AppLogger.storage.error("Failed to open recordings folder from permissions onboarding: \(String(describing: error), privacy: .public)")
        }
    }

    private func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }
}

private struct PermissionStatusRow: View {
    let title: String
    let state: RecorderPermissionState
    let explanation: String
    let actionTitle: String
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

            if state != .granted {
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
