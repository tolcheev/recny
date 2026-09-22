import AppKit
import SwiftUI
import RecnyCore

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
            if let prompt = appState.pendingAutoStartPrompt {
                pendingAutoStartContent(prompt)
            } else if appState.isRecordingStartAllowed {
                PrimaryRecordingButton(status: appState.status) {
                    startRecording()
                }
            } else {
                blockedRecordingContent
            }

            if let draft = appState.postCallDraft {
                postStopSummary(draft)
            }

            idleSummary
        }
    }

    private var blockedRecordingContent: some View {
        VStack(spacing: 12) {
            VStack(spacing: 7) {
                Label("Recording is blocked", systemImage: "exclamationmark.octagon.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.red)

                Text(appState.recordingStartBlockingReason ?? "Fix permissions before recording.")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Calls will not be recorded until this is fixed.")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            Button {
                PermissionActionHandler.handlePrimaryFixAction(appState: appState)
            } label: {
                Label(
                    appState.isPermissionOnboardingInProgress ? "Checking Permissions" : "Fix Permissions",
                    systemImage: appState.isPermissionOnboardingInProgress ? "hourglass" : "lock.shield"
                )
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 11)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(appState.isPermissionOnboardingInProgress)
            .accessibilityLabel("Fix Permissions")
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.red.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.red.opacity(0.58), lineWidth: 1.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Recording is blocked. \(appState.recordingStartBlockingReason ?? "Fix permissions before recording.")")
    }

    private func pendingAutoStartContent(_ prompt: PendingAutoStartPrompt) -> some View {
        VStack(spacing: 10) {
            Label("Call detected", systemImage: "phone.badge.waveform")
                .font(.headline)
                .foregroundStyle(Color.accentColor)

            Text("\(prompt.source.appName) looks like an active call.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 10) {
                Button {
                    appState.ignorePendingAutoStart()
                } label: {
                    Label("Ignore", systemImage: "xmark")
                }
                .accessibilityLabel("Ignore auto-start recording")

                Button {
                    confirmPendingAutoStart()
                } label: {
                    Label("Start Recording", systemImage: "record.circle")
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Start recording for detected call")
            }
        }
    }

    private func postStopSummary(_ draft: PostCallDraft) -> some View {
        VStack(spacing: 10) {
            VStack(spacing: 4) {
                Label(RecordingDisplayFormatter.statusText(draft.status), systemImage: "checkmark.circle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(draft.status == .failed ? .red : .green)

                Text(
                    RecordingDisplayFormatter.latestRecordingDetail(
                        status: draft.status,
                        duration: postStopDuration(for: draft),
                        micFileSizeBytes: fileSize(at: draft.sessionFolderURL.appendingPathComponent("source/mic.m4a")),
                        systemFileSizeBytes: fileSize(at: draft.sessionFolderURL.appendingPathComponent("source/system.m4a"))
                    )
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineLimit(2)
            }

            HStack(spacing: 8) {
                Button {
                    playRecording(draft)
                } label: {
                    Label("Play", systemImage: "play.fill")
                }
                .disabled(RecordingPlaybackResolver.preferredPlayback(sessionFolderURL: draft.sessionFolderURL) == nil)

                Button {
                    appState.editLastRecordingTags()
                } label: {
                    Label("Tag", systemImage: "tag")
                }

                Button {
                    NSWorkspace.shared.open(draft.sessionFolderURL)
                } label: {
                    Label("Show", systemImage: "folder")
                }
            }
            .controlSize(.small)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
        .accessibilityElement(children: .contain)
    }

    private var recordingContent: some View {
        VStack(alignment: .center, spacing: 16) {
            Text(appState.formattedDuration)
                .font(.system(size: 64, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .center)
                .accessibilityLabel("Current recording duration \(appState.formattedDuration)")

            PrimaryRecordingButton(status: appState.status, isBusy: appState.isStoppingRecording) {
                stopRecording()
            }

            VStack(spacing: 5) {
                Text(appState.isStoppingRecording ? "Finalizing audio files" : "Recording mic + system audio")
                    .font(.callout.weight(.medium))

                Label(
                    appState.isStoppingRecording
                        ? "Please keep the app open until saving finishes"
                        : "All system audio is being recorded",
                    systemImage: appState.isStoppingRecording ? "hourglass" : "speaker.wave.2"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        appState.isStoppingRecording
                            ? "Please keep the app open until saving finishes"
                            : "All system audio is being recorded"
                    )
            }

            VStack(spacing: 8) {
                LevelMeter(
                    label: "Mic level",
                    value: appState.microphoneLevel
                )
                LevelMeter(
                    label: "System audio level",
                    value: appState.systemAudioLevel
                )
            }
            .frame(maxWidth: 360)
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
                    if appState.isRecordingStartAllowed {
                        startRecording()
                    } else {
                        PermissionActionHandler.handlePrimaryFixAction(appState: appState)
                    }
                } label: {
                    Label(
                        errorActionTitle,
                        systemImage: appState.isRecordingStartAllowed ? "arrow.clockwise" : (appState.isPermissionOnboardingInProgress ? "hourglass" : "lock.shield")
                    )
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.isRecordingStartAllowed ? .accentColor : .orange)
                .disabled(!appState.isRecordingStartAllowed && appState.isPermissionOnboardingInProgress)
                .accessibilityLabel(errorActionTitle)
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
                    permissionState: appState.permissionSnapshot.screenSystemAudio,
                    captureStatus: appState.systemAudioStatus,
                    recordingStatus: appState.status,
                    isPermissionRequestInProgress: appState.isSystemAudioPermissionRequestInProgress
                )
            )
            summaryText(label: "Auto-start", value: autoStartSummary)

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

    private var errorActionTitle: String {
        if appState.isRecordingStartAllowed {
            return "Try Again"
        }
        return appState.isPermissionOnboardingInProgress ? "Checking Permissions" : "Fix Permissions"
    }

    private var autoStartSummary: String {
        switch appState.autoStartSettings.mode {
        case .off:
            return "Off"
        case .askFirst:
            return "Ask first"
        case .auto:
            return "On"
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
        AppLogger.file(.info, category: "recording", "stop requested source=main_window")
        Task {
            do {
                try await appState.stopRecording()
            } catch {
                AppLogger.recording.error("Stop recording from main window failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func confirmPendingAutoStart() {
        Task {
            do {
                try await appState.confirmPendingAutoStart()
            } catch {
                AppLogger.recording.error("Ask-first confirmation failed from main window: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func playRecording(_ draft: PostCallDraft) {
        guard let playback = RecordingPlaybackResolver.preferredPlayback(
            sessionFolderURL: draft.sessionFolderURL
        ) else {
            return
        }

        AppWindows.openAudioPlayer(
            url: playback.url,
            title: "\(draft.title) - \(playback.kind.displayName)"
        )
    }

    private func fileSize(at url: URL) -> Int64? {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path(percentEncoded: false)
        ),
              let size = attributes[.size] as? NSNumber,
              size.int64Value > 0
        else {
            return nil
        }

        return size.int64Value
    }

    private func postStopDuration(for draft: PostCallDraft) -> TimeInterval {
        guard appState.lastRecording?.id == draft.id else {
            return 0
        }

        return appState.lastRecording?.durationSec ?? 0
    }
}

private struct LevelMeter: View {
    let label: String
    let value: Float

    var body: some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 112, alignment: .leading)

            ProgressView(value: Double(value), total: 1)
                .progressViewStyle(.linear)
                .tint(value > 0.82 ? .orange : .accentColor)
                .accessibilityLabel(label)
                .accessibilityValue(value > 0.05 ? "Active" : "Silent")
        }
    }
}
