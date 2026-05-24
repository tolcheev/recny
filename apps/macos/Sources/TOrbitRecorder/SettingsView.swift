import AppKit
import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginMessage = ""
    @State private var launchAtLoginError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recordingSection
                autoStartSection
                storageSection
                hotkeysSection
                privacySection
                aboutSection
            }
            .padding(20)
        }
        .frame(width: 660, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshMicrophoneDevices()
            refreshLaunchAtLogin()
        }
    }

    private var recordingSection: some View {
        SettingsSection(title: "Recording") {
            Picker(
                "Audio quality",
                selection: Binding(
                    get: { appState.recordingSettings.audioQualityPreset },
                    set: { appState.setAudioQualityPreset($0) }
                )
            ) {
                ForEach(AudioQualityPreset.allCases, id: \.self) { preset in
                    Text(preset.displayName).tag(preset)
                }
            }

            Text("Standard is recommended for calls. Compact lowers AAC bitrate; High keeps more speech detail.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Preferred microphone",
                selection: Binding(
                    get: { appState.recordingSettings.microphoneDeviceID ?? DevicePriorityResolver.autoRecommendedID },
                    set: { appState.setPreferredMicrophoneDeviceID($0) }
                )
            ) {
                Text("Auto, recommended").tag(DevicePriorityResolver.autoRecommendedID)
                ForEach(appState.availableMicrophoneDevices) { device in
                    Text("\(device.name) · \(appState.microphoneDeviceLabel(for: device))").tag(device.id)
                }
            }

            Text("Auto prefers external or built-in mic. Avoids AirPods mic.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Text("Selected: \(appState.selectedMicrophoneName)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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

            if !appState.availableMicrophoneDevices.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Available inputs")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)

                    ForEach(appState.availableMicrophoneDevices) { device in
                        HStack(spacing: 8) {
                            Text(device.name)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer()

                            DeviceRoleBadge(text: appState.microphoneDeviceLabel(for: device))
                        }
                    }
                }
            }

            Toggle(
                "System audio recording",
                isOn: Binding(
                    get: { appState.recordingSettings.systemAudioEnabled },
                    set: { appState.setSystemAudioEnabled($0) }
                )
            )

            Toggle(
                "Mixed preview",
                isOn: Binding(
                    get: { appState.recordingSettings.mixedPreviewEnabled },
                    set: { appState.setMixedPreviewEnabled($0) }
                )
            )
        }
    }

    private var autoStartSection: some View {
        SettingsSection(title: "Auto-start") {
            Picker(
                "Mode",
                selection: Binding(
                    get: { appState.autoStartSettings.mode },
                    set: { appState.setAutoStartMode($0) }
                )
            ) {
                Text("Off").tag(AutoStartMode.off)
                Text("Ask first").tag(AutoStartMode.askFirst)
                Text("Auto").tag(AutoStartMode.auto)
            }
            .pickerStyle(.segmented)

            Text("Browser auto-start now looks for call-like window titles when available. YouTube-only browser detection is not perfect without a browser extension.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField(
                "Whitelist apps",
                text: Binding(
                    get: { joined(appState.autoStartSettings.whitelist) },
                    set: { appState.setAutoStartWhitelist(split($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            TextField(
                "Blacklist apps",
                text: Binding(
                    get: { joined(appState.autoStartSettings.blacklist) },
                    set: { appState.setAutoStartBlacklist(split($0)) }
                )
            )
            .textFieldStyle(.roundedBorder)

            Text("Optional blacklist hints: \(AutoStartSettings.defaultBlacklistHints.joined(separator: ", ")). Browsers are not blocked globally.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Stepper(
                value: Binding(
                    get: { appState.autoStartSettings.minDetectionDurationSeconds },
                    set: { appState.setAutoStartMinDetectionDurationSeconds($0) }
                ),
                in: 15...30,
                step: 5
            ) {
                Text("Detection duration: \(Int(appState.autoStartSettings.minDetectionDurationSeconds)) sec")
            }

            Stepper(
                value: Binding(
                    get: { appState.autoStartSettings.cooldownSeconds },
                    set: { appState.setAutoStartCooldownSeconds($0) }
                ),
                in: 60...600,
                step: 60
            ) {
                Text("Cooldown: \(Int(appState.autoStartSettings.cooldownSeconds / 60)) min")
            }

            Stepper(
                value: Binding(
                    get: { appState.autoStartSettings.shortRecordingThresholdSeconds },
                    set: { appState.setShortRecordingThresholdSeconds($0) }
                ),
                in: 15...300,
                step: 15
            ) {
                Text("Short recording threshold: \(Int(appState.autoStartSettings.shortRecordingThresholdSeconds)) sec")
            }
        }
    }

    private var storageSection: some View {
        SettingsSection(title: "Storage") {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local library location")
                    .font(.callout.weight(.medium))
                Text(appState.outputFolderPath)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            HStack(spacing: 8) {
                Button {
                    openOutputFolder()
                } label: {
                    Label("Open Library", systemImage: "folder")
                }

                Button {
                    chooseOutputFolder()
                } label: {
                    Label("Change Location", systemImage: "folder.badge.plus")
                }
                .disabled(appState.status == .recording)

                Button {
                    appState.resetStorageRootToDefault()
                } label: {
                    Label("Reset to Default", systemImage: "arrow.counterclockwise")
                }
                .disabled(isDefaultRoot || appState.status == .recording)
            }
        }
    }

    private var hotkeysSection: some View {
        SettingsSection(title: "Hotkeys") {
            ForEach(KeyboardShortcutCatalog.appActiveShortcuts) { shortcut in
                HStack(alignment: .firstTextBaseline) {
                    Text(shortcut.title)
                        .font(.callout)

                    Spacer()

                    Text(shortcut.displayText)
                        .font(.callout.monospaced().weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                }
            }

            Text("Shortcuts work when TOrbitRecorder is the active app. Global shortcuts are not part of this MVP step.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Custom shortcuts", text: .constant("Custom shortcuts coming later"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy / Behavior") {
            Toggle("Local-only mode", isOn: .constant(appState.privacySettings.localOnlyMode))
                .disabled(true)

            Text("MVP recordings stay on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Show recording indicator",
                isOn: Binding(
                    get: { appState.privacySettings.showRecordingIndicator },
                    set: { appState.setShowRecordingIndicator($0) }
                )
            )

            Toggle(
                "Show Dock icon",
                isOn: Binding(
                    get: { appState.privacySettings.showDockIcon },
                    set: { appState.setShowDockIcon($0) }
                )
            )

            Text("When off, TOrbitRecorder stays as a menu bar app. Use the menu bar item to show the window again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                )
            )

            Text("Starts TOrbitRecorder when you log in.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if !launchAtLoginMessage.isEmpty {
                Text(launchAtLoginMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let launchAtLoginError {
                Text(launchAtLoginError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }

            Toggle("Show Focus Mode reminder", isOn: .constant(appState.privacySettings.showFocusModeReminder))
                .disabled(true)
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "About") {
            SettingsInfoRow(label: "Version", value: BuildInfo.appVersion)
            SettingsInfoRow(label: "Build date", value: BuildInfo.buildDate)
            SettingsInfoRow(label: "Git commit", value: BuildInfo.gitCommit)
            SettingsInfoRow(label: "Local storage", value: appState.outputFolderPath, monospaced: true)
        }
    }

    private var isDefaultRoot: Bool {
        appState.outputFolderURL.path(percentEncoded: false) == RecordingPaths.defaultRoot.path(percentEncoded: false)
    }

    private func openOutputFolder() {
        do {
            try FileManager.default.createDirectory(
                at: appState.outputFolderURL,
                withIntermediateDirectories: true
            )
            NSWorkspace.shared.open(appState.outputFolderURL)
        } catch {
            AppLogger.storage.error("Failed to open output folder from settings: \(String(describing: error), privacy: .public)")
        }
    }

    private func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = appState.outputFolderURL
        panel.prompt = "Use Folder"

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        appState.setStorageRoot(url)
    }

    private func refreshLaunchAtLogin() {
        let snapshot = LaunchAtLoginController.snapshot()
        launchAtLoginEnabled = snapshot.isOn
        launchAtLoginMessage = snapshot.message
        launchAtLoginError = nil
        appState.setLaunchAtLoginPreference(snapshot.isOn)
    }

    private func setLaunchAtLogin(_ isEnabled: Bool) {
        do {
            let snapshot = try LaunchAtLoginController.setEnabled(isEnabled)
            launchAtLoginEnabled = snapshot.isOn
            launchAtLoginMessage = snapshot.message
            launchAtLoginError = nil
            appState.setLaunchAtLoginPreference(snapshot.isOn)
            AppLogger.file(.info, category: "app", "launch at login set enabled=\(snapshot.isOn) message=\(snapshot.message)")
        } catch {
            let snapshot = LaunchAtLoginController.snapshot()
            launchAtLoginEnabled = snapshot.isOn
            launchAtLoginMessage = snapshot.message
            launchAtLoginError = LaunchAtLoginController.humanReadableError(error)
            appState.setLaunchAtLoginPreference(snapshot.isOn)
            AppLogger.file(.error, category: "app", "launch at login update failed error=\(String(describing: error))")
        }
    }

    private func joined(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

private struct SettingsInfoRow: View {
    let label: String
    let value: String
    var monospaced = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.callout.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(width: 96, alignment: .leading)

            Text(value)
                .font(monospaced ? .caption.monospaced() : .callout)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 2)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}

struct DeviceRoleBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .lineLimit(1)
    }

    private var color: Color {
        switch text {
        case "Recommended":
            return .green
        case "Built-in":
            return .blue
        case "Bluetooth fallback":
            return .orange
        default:
            return .secondary
        }
    }
}
