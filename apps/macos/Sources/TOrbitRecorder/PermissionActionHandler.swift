import AppKit
import AVFoundation
import TOrbitRecorderCore

@MainActor
enum PermissionActionHandler {
    static func handlePrimaryFixAction(appState: AppState) {
        let snapshot = appState.permissionSnapshot
        if snapshot.microphone != .granted {
            handleMicrophoneAction(appState: appState)
            return
        }

        if appState.recordingSettings.systemAudioEnabled,
           snapshot.screenSystemAudio != .granted {
            openScreenSystemAudioSettings(appState: appState)
            return
        }

        if snapshot.storage != .granted {
            openRecordingsFolder(appState: appState)
            return
        }

        AppWindows.openDiagnostics(appState: appState)
    }

    static func handleMicrophoneAction(appState: AppState) {
        guard appState.permissionSnapshot.microphone == .notDetermined else {
            openMicrophoneSettings(appState: appState)
            return
        }

        Task {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
            await MainActor.run {
                appState.refreshPermissionSnapshot()
                if appState.permissionSnapshot.microphone != .granted {
                    openMicrophoneSettings(appState: appState)
                }
            }
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
        let shellCommand = "sleep 0.8; open \(shellQuoted(reopenedBundlePath))"

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

    private static func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
