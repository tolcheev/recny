import Foundation

public enum PermissionRequirement: String, CaseIterable, Sendable {
    case microphone
    case screenSystemAudio
    case storage
}

public enum PermissionOnboardingFormatter {
    public static let restartMessage = "Permission is enabled. Restart ToRec to apply it."

    public static func title(for requirement: PermissionRequirement) -> String {
        switch requirement {
        case .microphone:
            return "Microphone"
        case .screenSystemAudio:
            return "System audio"
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
            return "ToRec cannot determine microphone permission."

        case (.screenSystemAudio, .granted):
            return "System audio recording is available."
        case (.screenSystemAudio, .restartRequired):
            return restartMessage
        case (.screenSystemAudio, .denied):
            return "System audio access is denied. Enable it in System Settings, then restart the app."
        case (.screenSystemAudio, .missing):
            return "Required for source/system.m4a and mixed preview. Request access before recording."
        case (.screenSystemAudio, .notDetermined):
            return "Use Fix Permissions to request system audio access before recording. macOS calls this Screen & System Audio Recording, but ToRec records only audio, not screen video."
        case (.screenSystemAudio, .unknown):
            return "ToRec cannot determine system audio permission."

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
            return "ToRec cannot determine output folder access."
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
            switch state {
            case .notDetermined, .missing:
                return "Request System Audio Access"
            default:
                return "Open System Audio Settings"
            }
        case .storage:
            return "Open Library"
        }
    }

    public static func inlineActionTitle(
        for requirement: PermissionRequirement,
        state: RecorderPermissionState
    ) -> String? {
        guard state != .granted else {
            return nil
        }

        switch (requirement, state) {
        case (.microphone, .notDetermined),
             (.screenSystemAudio, .notDetermined),
             (.storage, .notDetermined):
            return nil
        default:
            return actionTitle(for: requirement, state: state)
        }
    }

    public static func requiresRestart(_ snapshot: RecorderPermissionSnapshot) -> Bool {
        snapshot.microphone == .restartRequired
            || snapshot.screenSystemAudio == .restartRequired
            || snapshot.storage == .restartRequired
    }

    public static func reopenInstruction(bundlePath: String) -> String {
        let trimmedPath = bundlePath.trimmingCharacters(in: .whitespacesAndNewlines)
        let path = trimmedPath.isEmpty ? "/Applications/ToRec.app" : trimmedPath
        return "After quitting, reopen the same app bundle you approved in System Settings:\nopen \"\(path)\""
    }
}
