import AppKit
import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                recordingSection
                autoStartSection
                storageSection
                hotkeysSection
                privacySection
            }
            .padding(20)
        }
        .frame(width: 620, height: 640)
    }

    private var recordingSection: some View {
        SettingsSection(title: "Recording") {
            Picker("Audio quality preset", selection: .constant(appState.recordingSettings.audioQualityPreset)) {
                Text("Standard AAC 48 kHz").tag(AudioQualityPreset.standard)
            }
            .disabled(true)

            TextField("Mic device", text: .constant("Default system input"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            Toggle(
                "System audio enabled",
                isOn: Binding(
                    get: { appState.recordingSettings.systemAudioEnabled },
                    set: { appState.setSystemAudioEnabled($0) }
                )
            )

            Toggle(
                "Mixed preview enabled",
                isOn: Binding(
                    get: { appState.recordingSettings.mixedPreviewEnabled },
                    set: { appState.setMixedPreviewEnabled($0) }
                )
            )
        }
    }

    private var autoStartSection: some View {
        SettingsSection(title: "Auto-start") {
            Toggle(
                "Enabled",
                isOn: Binding(
                    get: { appState.autoStartSettings.isEnabled },
                    set: { appState.setAutoStartEnabled($0) }
                )
            )

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

            Text("Last decision: \(appState.autoStartLastDecision)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
    }

    private var storageSection: some View {
        SettingsSection(title: "Storage") {
            Text(appState.outputFolderPath)
                .font(.callout.monospaced())
                .textSelection(.enabled)

            HStack(spacing: 8) {
                Button {
                    chooseOutputFolder()
                } label: {
                    Label("Choose Folder", systemImage: "folder.badge.plus")
                }
                .disabled(appState.status == .recording)

                Button {
                    openOutputFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }

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
            TextField("Start/stop hotkey", text: .constant("Not configured in MVP"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            TextField("Add marker", text: .constant("Later"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
            Toggle("Local-only mode", isOn: .constant(appState.privacySettings.localOnlyMode))
                .disabled(true)

            Toggle(
                "Show recording indicator",
                isOn: Binding(
                    get: { appState.privacySettings.showRecordingIndicator },
                    set: { appState.setShowRecordingIndicator($0) }
                )
            )

            Toggle("Show Focus Mode reminder", isOn: .constant(appState.privacySettings.showFocusModeReminder))
                .disabled(true)
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

    private func joined(_ values: [String]) -> String {
        values.joined(separator: ", ")
    }

    private func split(_ value: String) -> [String] {
        value.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
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
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
