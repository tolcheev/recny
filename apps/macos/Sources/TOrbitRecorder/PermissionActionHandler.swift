import AppKit
import AVFoundation
import TOrbitRecorderCore

@MainActor
enum PermissionActionHandler {
    static func handlePrimaryFixAction(appState: AppState) {
        Task { @MainActor in
            await requestMissingPermissions(appState: appState)
        }
    }

    static func handleMicrophoneAction(appState: AppState) {
        Task { @MainActor in
            _ = await requestMicrophoneAccessOrOpenSettings(appState: appState)
        }
    }

    static func handleSystemAudioAction(appState: AppState) {
        Task { @MainActor in
            _ = await requestSystemAudioAccessOrOpenSettings(appState: appState)
        }
    }

    static func openMicrophoneSettings(appState: AppState) {
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        appState.refreshPermissionSnapshot()
    }

    static func openScreenSystemAudioSettings(appState: AppState) {
        appState.markScreenSystemAudioSettingsOpened()
        openSystemSettings("x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")
    }

    static func openRecordingsFolder(appState: AppState) {
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

    static func restartApp() {
        let bundlePath = Bundle.main.bundleURL.path(percentEncoded: false)
        let reopenedBundlePath = FileManager.default.fileExists(atPath: "/Applications/TOrbitRecorder.app")
            ? "/Applications/TOrbitRecorder.app"
            : bundlePath
        let shellCommand = AppRestartCommand.shellCommand(
            currentProcessID: ProcessInfo.processInfo.processIdentifier,
            bundlePath: reopenedBundlePath
        )

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", shellCommand]

        do {
            try process.run()
            AppLogger.file(.info, category: "permissions", "restart requested bundle=\(reopenedBundlePath)")
        } catch {
            AppLogger.file(.error, category: "permissions", "restart launch failed bundle=\(reopenedBundlePath) error=\(String(describing: error))")
        }

        NSApp.terminate(nil)
    }

    private static func openSystemSettings(_ rawURL: String) {
        guard let url = URL(string: rawURL) else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    private static func requestMissingPermissions(appState: AppState) async {
        appState.beginPermissionOnboarding(message: "Checking recording permissions...")
        appState.refreshMicrophoneDevices()
        appState.refreshPermissionSnapshot()

        if appState.permissionSnapshot.microphone != .granted {
            appState.updatePermissionOnboardingMessage("Requesting microphone access...")
            let willRequestSystemAudioAfterMicrophone = appState.recordingSettings.systemAudioEnabled
                && appState.permissionSnapshot.screenSystemAudio != .granted
            let microphoneGranted = await requestMicrophoneAccessOrOpenSettings(
                appState: appState,
                nextPrompt: willRequestSystemAudioAfterMicrophone ? .systemAudio : nil
            )
            guard microphoneGranted else {
                appState.completePermissionOnboarding(
                    message: "Microphone access is still required.",
                    clearAfter: nil
                )
                return
            }
            appState.updatePermissionOnboardingMessage("Microphone access granted. Requesting system audio access...")
            await prepareForNextPermissionPrompt()
        }

        appState.refreshPermissionSnapshot()
        if appState.recordingSettings.systemAudioEnabled,
           appState.permissionSnapshot.screenSystemAudio != .granted {
            appState.updatePermissionOnboardingMessage("Requesting system audio access...")
            let systemAudioGranted = await requestSystemAudioAccessOrOpenSettings(appState: appState)
            appState.refreshPermissionSnapshot()
            guard systemAudioGranted, appState.permissionSnapshot.screenSystemAudio == .granted else {
                appState.completePermissionOnboarding(
                    message: "System audio access is still required.",
                    clearAfter: nil
                )
                return
            }
            appState.updatePermissionOnboardingMessage("System audio access verified.")
        } else if appState.recordingSettings.systemAudioEnabled {
            appState.updatePermissionOnboardingMessage("System audio access already verified.")
        }

        if appState.permissionSnapshot.storage != .granted {
            appState.completePermissionOnboarding(
                message: "The recordings folder needs to be writable.",
                clearAfter: nil
            )
            openRecordingsFolder(appState: appState)
            return
        }

        appState.completePermissionOnboarding(
            message: "Microphone and system audio access are ready. macOS skips prompts that were already granted."
        )
        AppLogger.file(.info, category: "permissions", "permission onboarding completed without opening diagnostics")
    }

    private static func requestMicrophoneAccessOrOpenSettings(
        appState: AppState,
        nextPrompt: PermissionPromptKind? = nil
    ) async -> Bool {
        guard appState.permissionSnapshot.microphone == .notDetermined else {
            openMicrophoneSettings(appState: appState)
            return appState.permissionSnapshot.microphone == .granted
        }

        AppLogger.file(.info, category: "permissions", "microphone permission request started from onboarding")
        await waitBeforeMicrophonePermissionPrompt()
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        AppLogger.file(.info, category: "permissions", "microphone permission request finished granted=\(granted)")
        appState.refreshPermissionSnapshot()
        if !granted {
            openMicrophoneSettings(appState: appState)
            return false
        } else {
            await waitForMicrophoneGrant(appState: appState)
            refocusMainWindowIfAllowed(after: .microphone, nextPrompt: nextPrompt)
        }

        return true
    }

    private static func requestSystemAudioAccessOrOpenSettings(appState: AppState) async -> Bool {
        appState.refreshPermissionSnapshot()
        switch appState.permissionSnapshot.screenSystemAudio {
        case .granted:
            return true
        case .notDetermined, .missing:
            do {
                AppLogger.file(.info, category: "permissions", "system audio permission request started from onboarding")
                await waitBeforeSystemAudioPermissionPrompt()
                try await ScreenCaptureKitSystemAudioRecorder.requestSystemAudioAccess()
                appState.noteSystemAudioPermissionRequestSucceeded()
                refocusMainWindowIfAllowed(after: .systemAudio)
            } catch {
                AppLogger.file(.error, category: "permissions", "system audio permission request failed error=\(String(describing: error))")
                appState.noteSystemAudioPermissionRequestFailed(error)
                refocusMainWindowIfAllowed(after: .systemAudio)
            }
            return appState.permissionSnapshot.screenSystemAudio == .granted
        case .denied, .restartRequired, .unknown:
            openScreenSystemAudioSettings(appState: appState)
            return false
        }
    }

    private static func refocusMainWindowIfAllowed(
        after completedPrompt: PermissionPromptKind,
        nextPrompt: PermissionPromptKind? = nil
    ) {
        guard PermissionPromptSequencePolicy.shouldRefocusMainWindow(
            after: completedPrompt,
            next: nextPrompt
        ) else {
            AppLogger.file(.info, category: "permissions", "skipping main window refocus after \(completedPrompt) permission prompt")
            return
        }

        refocusMainWindowAfterPermissionPrompt()
    }

    private static func refocusMainWindowAfterPermissionPrompt() {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)
            AppLogger.file(.info, category: "permissions", "requesting main window focus after permission prompt")
            AppWindowRequest.postShowMainWindow(reason: .permissionPromptCompleted)
        }
    }

    private static func prepareForNextPermissionPrompt() async {
        AppLogger.file(.info, category: "permissions", "waiting before next permission prompt without changing window z-order")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
    }

    private static func waitBeforeSystemAudioPermissionPrompt() async {
        AppLogger.file(.info, category: "permissions", "waiting before system audio permission prompt without changing window z-order")
        try? await Task.sleep(nanoseconds: 300_000_000)
    }

    private static func waitBeforeMicrophonePermissionPrompt() async {
        AppLogger.file(.info, category: "permissions", "waiting before microphone permission prompt without changing window z-order")
        try? await Task.sleep(nanoseconds: 150_000_000)
    }

    private static func waitForMicrophoneGrant(appState: AppState) async {
        for _ in 0..<5 {
            appState.refreshPermissionSnapshot()
            if appState.permissionSnapshot.microphone == .granted {
                return
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        appState.refreshPermissionSnapshot()
    }
}
