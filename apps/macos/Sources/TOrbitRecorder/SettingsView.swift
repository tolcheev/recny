import AppKit
import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recordingSection
                autoStartSection
                storageSection
                hotkeysSection
                privacySection
            }
            .padding(20)
        }
        .frame(width: 660, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var recordingSection: some View {
        SettingsSection(title: "Recording") {
            Picker("Audio quality", selection: .constant("standard")) {
                Text("Compact").tag("compact")
                Text("Standard").tag("standard")
                Text("High").tag("high")
            }
            .disabled(true)

            Text("Quality presets are coming later. MVP uses Standard AAC 48 kHz.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Preferred microphone",
                selection: Binding(
                    get: { appState.recordingSettings.microphoneDeviceID ?? MicrophoneDeviceResolver.autoRecommendedID },
                    set: { appState.setPreferredMicrophoneDeviceID($0) }
                )
            ) {
                Text("Auto, recommended").tag(MicrophoneDeviceResolver.autoRecommendedID)
                ForEach(appState.availableMicrophoneDevices) { device in
                    Text(device.name).tag(device.id)
                }
            }

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
            Toggle(
                "Auto-start enabled",
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
            TextField("Start/stop hotkey", text: .constant("Coming later"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)

            TextField("Add marker", text: .constant("Coming later"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
        }
    }

    private var privacySection: some View {
        SettingsSection(title: "Privacy") {
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
            .padding(.vertical, 2)
        } label: {
            Text(title)
                .font(.headline)
        }
    }
}
