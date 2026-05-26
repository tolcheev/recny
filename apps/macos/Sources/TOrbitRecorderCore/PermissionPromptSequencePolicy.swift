import Foundation

public enum PermissionPromptKind: Sendable {
    case microphone
    case systemAudio
}

public enum PermissionPromptSequencePolicy {
    public static func shouldRefocusMainWindow(
        after completedPrompt: PermissionPromptKind,
        next nextPrompt: PermissionPromptKind?
    ) -> Bool {
        if completedPrompt == .systemAudio {
            return false
        }

        return !(completedPrompt == .microphone && nextPrompt == .systemAudio)
    }
}
