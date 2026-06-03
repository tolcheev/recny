import Foundation

public enum PermissionRecheckMode: Equatable, Sendable {
    case normal
    case forced
}

public enum PermissionRecheckPolicy {
    public static func shouldInvalidateSystemAudioProbeCache(
        mode: PermissionRecheckMode,
        systemAudioEnabled: Bool
    ) -> Bool {
        guard systemAudioEnabled else {
            return false
        }

        switch mode {
        case .normal:
            return false
        case .forced:
            return true
        }
    }
}
