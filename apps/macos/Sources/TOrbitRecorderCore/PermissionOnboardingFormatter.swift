import Foundation

public enum PermissionRequirement: String, CaseIterable, Sendable {
    case microphone
    case screenSystemAudio
    case storage
}

public enum PermissionOnboardingFormatter {
    public static let restartMessage = "Permission is enabled. Restart TOrbitRecorder to apply it."

    public static func title(for requirement: PermissionRequirement) -> String {
        switch requirement {
        case .microphone:
            return "Microphone"
        case .screenSystemAudio:
            return "Screen & System Audio Recording"
        case .storage:
            return "Output folder writable"
        }
    }

    public static func explanation(
        for requirement: PermissionRequirement,
        state: RecorderPermissionState
    ) -> String {
        switch (requirement, state) {
        case (.microphone, .granted):
            return "Microphone recording is available."
        case (.microphone, .notDetermined):
            return "macOS has not asked for microphone access yet."
        case (.microphone, .denied):
            return "Microphone access is denied. Enable it in System Settings."
        case (.microphone, .restartRequired):
            return restartMessage
        case (.microphone, .missing):
            return "Microphone access is required for source/mic.m4a."
        case (.microphone, .unknown):
            return "TOrbitRecorder cannot determine microphone permission."

        case (.screenSystemAudio, .granted):
            return "System audio recording is available."
        case (.screenSystemAudio, .restartRequired):
            return restartMessage
        case (.screenSystemAudio, .denied):
            return "System audio access is denied. Enable it in System Settings, then restart the app."
        case (.screenSystemAudio, .missing):
            return "Required for source/system.m4a and mixed preview."
        case (.screenSystemAudio, .notDetermined):
            return "macOS has not granted Screen & System Audio Recording access yet."
        case (.screenSystemAudio, .unknown):
            return "TOrbitRecorder cannot determine system audio permission."

        case (.storage, .granted):
            return "The local recordings folder is writable."
        case (.storage, .denied):
            return "The recordings folder is not writable. Pick or fix a writable local folder."
        case (.storage, .restartRequired):
            return "Storage permission changed. Restart if macOS still blocks the folder."
        case (.storage, .missing):
            return "The recordings folder must exist and be writable."
        case (.storage, .notDetermined):
            return "The app has not confirmed write access to the recordings folder yet."
        case (.storage, .unknown):
            return "TOrbitRecorder cannot determine output folder access."
        }
    }

    public static func actionTitle(
        for requirement: PermissionRequirement,
        state: RecorderPermissionState
    ) -> String {
        switch requirement {
        case .microphone:
            return state == .notDetermined ? "Request Microphone Access" : "Open Microphone Settings"
        case .screenSystemAudio:
            return "Open Screen & System Audio Recording Settings"
        case .storage:
            return "Open Recordings Folder"
        }
    }

    public static func requiresRestart(_ snapshot: RecorderPermissionSnapshot) -> Bool {
        snapshot.microphone == .restartRequired
            || snapshot.screenSystemAudio == .restartRequired
            || snapshot.storage == .restartRequired
    }

    public static func reopenInstruction(bundlePath: String) -> String {
        let trimmedPath = bundlePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmedPath.isEmpty ? "/Applications/TOrbitRecorder.app" : trimmedPath
        return "After quitting, reopen the same app bundle you approved in System Settings:\nopen \"\(path)\""
    }
}
