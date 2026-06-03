import AppKit
import SwiftUI
import TOrbitRecorderCore

struct SettingsView: View {
    @ObservedObject var appState: AppState
    @State private var launchAtLoginEnabled = false
    @State private var launchAtLoginMessage = ""
    @State private var launchAtLoginError: String?
    @State private var transcriptionSetupStatus = LocalTranscriptionSetupInspector.status()
    @State private var transcriptionSetupMessage: String?
    @State private var transcriptionSetupError: String?
    @State private var isPreparingTranscription = false
    @State private var updateCheckMessage: String?
    @State private var updateCheckError: String?
    @State private var latestUpdateRelease: AppUpdateRelease?
    @State private var isCheckingForUpdates = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                recordingSection
                transcriptionSection
                autoStartSection
                storageSection
                hotkeysSection
                behaviorSection
                aboutSection
            }
            .padding(20)
        }
        .frame(width: 660, height: 680)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            appState.refreshMicrophoneDevices()
            refreshLaunchAtLogin()
            refreshTranscriptionSetup()
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
                if let unavailableDeviceID = unavailablePreferredMicrophoneDeviceID {
                    Text("Selected device unavailable").tag(unavailableDeviceID)
                }
                ForEach(appState.availableMicrophoneDevices) { device in
                    Text("\(device.name) · \(appState.microphoneDeviceLabel(for: device))")
                        .tag(device.id)
                        .disabled(DevicePriorityResolver.isBluetoothHeadset(device))
                }
            }

            Text("Auto uses external or built-in microphones only. AirPods and other Bluetooth headset mics are blocked for recording.")
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

            RequiredRecordingOutputRow(
                label: "System audio recording",
                detail: "Required for MVP output: source/system.m4a"
            )

            RequiredRecordingOutputRow(
                label: "Mixed export",
                detail: "Required for MVP output: export/mixed.m4a"
            )

            Divider()

            Toggle(
                "Volume leveling",
                isOn: Binding(
                    get: { appState.recordingSettings.audioLevelingEnabled },
                    set: { appState.setAudioLevelingEnabled($0) }
                )
            )

            Text("Creates export/mixed_balanced.m4a after Stop. Raw mic and system files are not changed.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker(
                "Leveling mode",
                selection: Binding(
                    get: { appState.recordingSettings.audioLevelingMode },
                    set: { appState.setAudioLevelingMode($0) }
                )
            ) {
                Text(AudioLevelingMode.balanced.displayName).tag(AudioLevelingMode.balanced)
                Text(AudioLevelingMode.conservative.displayName).tag(AudioLevelingMode.conservative)
                Text("\(AudioLevelingMode.voiceBoost.displayName) · Coming later")
                    .tag(AudioLevelingMode.voiceBoost)
                    .disabled(true)
            }
            .disabled(!appState.recordingSettings.audioLevelingEnabled)

            Text(levelingModeHelp)
                .font(.caption)
                .foregroundStyle(.secondary)
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

            Text("Browser auto-start requires a call-like active window title. If macOS does not expose the title, the browser signal is ignored.")
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

            Picker(
                "Auto-stop delay",
                selection: Binding(
                    get: { appState.autoStartSettings.autoStopDelaySeconds },
                    set: { appState.setAutoStopDelaySeconds($0) }
                )
            ) {
                ForEach(AutoStartSettings.allowedAutoStopDelays, id: \.self) { value in
                    Text("\(Int(value)) sec").tag(value)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Auto-stop delay")

            Text("Time to wait after the call signal is lost before stopping an auto-started recording.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var transcriptionSection: some View {
        SettingsSection(title: "Local transcription") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: transcriptionSetupStatus.canTranscribeWithoutSetup ? "checkmark.circle.fill" : "arrow.down.circle")
                    .foregroundStyle(transcriptionSetupStatus.canTranscribeWithoutSetup ? .green : .orange)

                VStack(alignment: .leading, spacing: 4) {
                    Text(transcriptionSetupStatus.displayText)
                        .font(.callout.weight(.medium))
                    Text(transcriptionSetupStatus.actionHint)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }

                Spacer()

                Button {
                    refreshTranscriptionSetup()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }

            Text("Optional add-on. ToRec does not bundle models and does not download them from Records. Prepare Parakeet here first; after that Records can transcribe locally without a first-run model download.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                Button {
                    prepareTranscriptionModel()
                } label: {
                    Label(isPreparingTranscription ? "Preparing..." : "Prepare Parakeet Model", systemImage: "arrow.down.circle")
                }
                .disabled(isPreparingTranscription || !canPrepareTranscriptionModel)

                Button {
                    copyTranscriptionInstallCommand()
                } label: {
                    Label("Copy Install Command", systemImage: "doc.on.doc")
                }

                if transcriptionSetupStatus.canTranscribeWithoutSetup {
                    Text("Ready")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.green)
                }
            }

            Text("Install command: brew install uv ffmpeg && uv tool install parakeet-mlx -U")
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            if let transcriptionSetupMessage {
                Label(transcriptionSetupMessage, systemImage: "checkmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let transcriptionSetupError {
                Label(transcriptionSetupError, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
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

            HStack(alignment: .firstTextBaseline) {
                Text("\(KeyboardShortcutCatalog.showWindowGlobal.title) while another app is active")
                    .font(.callout)

                Spacer()

                Text(KeyboardShortcutCatalog.showWindowGlobal.displayText)
                    .font(.callout.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }

            HStack(alignment: .firstTextBaseline) {
                Text("\(KeyboardShortcutCatalog.captureScreenshotGlobal.title) while another app is active")
                    .font(.callout)

                Spacer()

                Text(KeyboardShortcutCatalog.captureScreenshotGlobal.displayText)
                    .font(.callout.monospaced().weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
            }

            Text("Recording, Library, Diagnostics, and app-active Screenshot shortcuts work when ToRec is active. Show Window and full-screen Screenshot also have global shortcuts for call moments.")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Custom shortcuts", text: .constant("Custom shortcuts coming later"))
                .textFieldStyle(.roundedBorder)
                .disabled(true)
        }
    }

    private var behaviorSection: some View {
        SettingsSection(title: "Behavior") {
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

            Text("Off by default. ToRec stays in the menu bar; use the menu bar item to show the window again.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Toggle(
                "Launch at Login",
                isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                )
            )

            Text("On by default so auto-start is available after you log in.")
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

            Divider()

            HStack(spacing: 8) {
                Button {
                    checkForUpdates()
                } label: {
                    Label(isCheckingForUpdates ? "Checking..." : "Check for Updates", systemImage: "arrow.down.circle")
                }
                .disabled(isCheckingForUpdates)

                Button {
                    openUpdateDownload()
                } label: {
                    Label("Download Update", systemImage: "square.and.arrow.down")
                }
                .disabled(latestUpdateRelease == nil)

                Button {
                    openUpdateReleasePage()
                } label: {
                    Label("Release Page", systemImage: "safari")
                }
                .disabled(latestUpdateRelease == nil)

                Button {
                    openBugReport()
                } label: {
                    Label("Report Bug", systemImage: "ladybug")
                }
            }

            Text("Updates are downloaded from the public GitHub release page. ToRec does not overwrite itself automatically. Report Bug opens the public structured bug form.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let updateCheckMessage {
                Text(updateCheckMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            if let updateCheckError {
                Text(updateCheckError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
    }

    private var isDefaultRoot: Bool {
        appState.outputFolderURL.path(percentEncoded: false) == RecordingPaths.defaultRoot.path(percentEncoded: false)
    }

    private var unavailablePreferredMicrophoneDeviceID: String? {
        guard let preferredID = appState.recordingSettings.microphoneDeviceID,
              !preferredID.isEmpty,
              !appState.availableMicrophoneDevices.contains(where: { $0.id == preferredID })
        else {
            return nil
        }

        return preferredID
    }

    private var levelingModeHelp: String {
        switch appState.recordingSettings.audioLevelingMode {
        case .balanced:
            return "Balanced evens out microphone and system audio for normal listening."
        case .conservative:
            return "Conservative uses smaller gain changes when the original recording already sounds usable."
        case .voiceBoost:
            return "Voice Boost is reserved for a later speech-focused processing pass."
        }
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
        do {
            let snapshot = appState.privacySettings.launchAtLogin
                ? try LaunchAtLoginController.setEnabled(true)
                : LaunchAtLoginController.snapshot()
            launchAtLoginEnabled = snapshot.isOn
            launchAtLoginMessage = snapshot.message
            launchAtLoginError = nil
            appState.setLaunchAtLoginPreference(snapshot.isOn)
        } catch {
            let snapshot = LaunchAtLoginController.snapshot()
            let errorMessage = LaunchAtLoginController.humanReadableError(error)
            launchAtLoginEnabled = appState.privacySettings.launchAtLogin
            launchAtLoginMessage = snapshot.message
            launchAtLoginError = errorMessage
            appState.setLaunchAtLoginPreference(appState.privacySettings.launchAtLogin, errorMessage: errorMessage)
        }
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
            let errorMessage = LaunchAtLoginController.humanReadableError(error)
            launchAtLoginEnabled = snapshot.isOn
            launchAtLoginMessage = snapshot.message
            launchAtLoginError = errorMessage
            appState.setLaunchAtLoginPreference(snapshot.isOn, errorMessage: errorMessage)
            AppLogger.file(.error, category: "app", "launch at login update failed error=\(String(describing: error))")
        }
    }

    private var canPrepareTranscriptionModel: Bool {
        if case .needsModelDownload = transcriptionSetupStatus {
            return true
        }
        return false
    }

    private func refreshTranscriptionSetup() {
        transcriptionSetupStatus = LocalTranscriptionSetupInspector.status()
    }

    private func prepareTranscriptionModel() {
        guard !isPreparingTranscription else {
            return
        }

        isPreparingTranscription = true
        transcriptionSetupError = nil
        transcriptionSetupMessage = "Downloading and preparing Parakeet model locally. This can take a few minutes once."

        Task {
            do {
                try await LocalTranscriptionRunner().prepareParakeetModel()
                refreshTranscriptionSetup()
                transcriptionSetupError = nil
                transcriptionSetupMessage = "Parakeet model is prepared. Records can transcribe locally now."
            } catch let error as LocalTranscriptionError {
                refreshTranscriptionSetup()
                transcriptionSetupError = error.description
                transcriptionSetupMessage = nil
            } catch {
                refreshTranscriptionSetup()
                transcriptionSetupError = String(describing: error)
                transcriptionSetupMessage = nil
            }
            isPreparingTranscription = false
        }
    }

    private func copyTranscriptionInstallCommand() {
        let command = "brew install uv ffmpeg && uv tool install parakeet-mlx -U"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        transcriptionSetupError = nil
        transcriptionSetupMessage = "Install command copied."
    }

    private func checkForUpdates() {
        guard !isCheckingForUpdates else {
            return
        }

        isCheckingForUpdates = true
        updateCheckError = nil
        updateCheckMessage = "Checking latest ToRec release..."

        Task {
            do {
                let result = try await AppUpdateChecker().check(
                    platform: .macOS,
                    currentVersion: BuildInfo.appVersion
                )
                latestUpdateRelease = result.isUpdateAvailable ? result.latestRelease : nil
                updateCheckMessage = result.displayText
                updateCheckError = nil
                AppLogger.file(
                    .info,
                    category: "app",
                    "update check completed current=\(result.currentVersion) latest=\(result.latestRelease.version) available=\(result.isUpdateAvailable)"
                )
            } catch {
                latestUpdateRelease = nil
                updateCheckMessage = nil
                updateCheckError = "Could not check updates: \(String(describing: error))"
                AppLogger.file(.error, category: "app", "update check failed error=\(String(describing: error))")
            }
            isCheckingForUpdates = false
        }
    }

    private func openUpdateDownload() {
        guard let latestUpdateRelease else {
            return
        }

        NSWorkspace.shared.open(latestUpdateRelease.downloadURL)
    }

    private func openUpdateReleasePage() {
        guard let latestUpdateRelease else {
            return
        }

        NSWorkspace.shared.open(latestUpdateRelease.releaseURL)
    }

    private func openBugReport() {
        guard let url = AppSupportLinks.bugReportURL(
            version: BuildInfo.appVersion,
            platform: .macOS
        ) else {
            return
        }

        NSWorkspace.shared.open(url)
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

private struct RequiredRecordingOutputRow: View {
    let label: String
    let detail: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.callout.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Always on")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
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
        case "Blocked":
            return .red
        default:
            return .secondary
        }
    }
}
