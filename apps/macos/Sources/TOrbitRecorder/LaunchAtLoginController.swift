import Foundation
import ServiceManagement

struct LaunchAtLoginSnapshot: Equatable {
    let isOn: Bool
    let message: String
}

enum LaunchAtLoginController {
    static func snapshot() -> LaunchAtLoginSnapshot {
        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginSnapshot(
                isOn: true,
                message: "Enabled. TOrbitRecorder starts when you log in."
            )
        case .requiresApproval:
            return LaunchAtLoginSnapshot(
                isOn: true,
                message: "Requires approval in System Settings -> General -> Login Items."
            )
        case .notRegistered:
            return LaunchAtLoginSnapshot(
                isOn: false,
                message: "Off. TOrbitRecorder will not start automatically."
            )
        case .notFound:
            return LaunchAtLoginSnapshot(
                isOn: false,
                message: "Login item service is not available for this app bundle."
            )
        @unknown default:
            return LaunchAtLoginSnapshot(
                isOn: false,
                message: "Launch at Login status is unknown."
            )
        }
    }

    static func setEnabled(_ isEnabled: Bool) throws -> LaunchAtLoginSnapshot {
        if isEnabled {
            if SMAppService.mainApp.status != .enabled {
                try SMAppService.mainApp.register()
            }
        } else if SMAppService.mainApp.status != .notRegistered {
            try SMAppService.mainApp.unregister()
        }

        return snapshot()
    }

    static func humanReadableError(_ error: Error) -> String {
        let details = (error as NSError).localizedDescription
        return "Could not update Launch at Login. Run the installed app bundle from /Applications and try again. Details: \(details)"
    }
}
