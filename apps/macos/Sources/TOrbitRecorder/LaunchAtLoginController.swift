import Foundation
import ServiceManagement

struct LaunchAtLoginSnapshot: Equatable {
    let isOn: Bool
    let message: String
}

enum LaunchAtLoginController {
    static func snapshot() -> LaunchAtLoginSnapshot {
        if LaunchAgentLoginItemStore.isRegistered {
            return LaunchAtLoginSnapshot(
                isOn: true,
                message: "Enabled via local login agent. ToRec starts when you log in."
            )
        }

        switch SMAppService.mainApp.status {
        case .enabled:
            return LaunchAtLoginSnapshot(
                isOn: true,
                message: "Enabled. ToRec starts when you log in."
            )
        case .requiresApproval:
            return LaunchAtLoginSnapshot(
                isOn: true,
                message: "Requires approval in System Settings -> General -> Login Items."
            )
        case .notRegistered:
            return LaunchAtLoginSnapshot(
                isOn: false,
                message: "Off. ToRec will not start automatically."
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
            if SMAppService.mainApp.status == .notFound {
                try LaunchAgentLoginItemStore.register()
                return snapshot()
            }

            if SMAppService.mainApp.status != .enabled,
               SMAppService.mainApp.status != .requiresApproval {
                do {
                    try SMAppService.mainApp.register()
                } catch {
                    try LaunchAgentLoginItemStore.register()
                    return snapshot()
                }
            }
        } else {
            try LaunchAgentLoginItemStore.unregister()
            if SMAppService.mainApp.status != .notRegistered,
               SMAppService.mainApp.status != .notFound {
                try SMAppService.mainApp.unregister()
            }
        }

        return snapshot()
    }

    static func humanReadableError(_ error: Error) -> String {
        let details = (error as NSError).localizedDescription
        return "Could not update Launch at Login. Run the installed app bundle from /Applications and try again. Details: \(details)"
    }
}

private enum LaunchAgentLoginItemStore {
    private static let label = "com.torbit.recorder.login"

    private static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent("\(label).plist")
    }

    private static var launchAppURL: URL {
        let installedURL = URL(fileURLWithPath: "/Applications/ToRec.app")
        if FileManager.default.fileExists(atPath: installedURL.path),
           Bundle(url: installedURL)?.bundleIdentifier == Bundle.main.bundleIdentifier {
            return installedURL
        }

        return Bundle.main.bundleURL
    }

    static var isRegistered: Bool {
        guard let plist = NSDictionary(contentsOf: plistURL) as? [String: Any],
              plist["Label"] as? String == label,
              let arguments = plist["ProgramArguments"] as? [String]
        else {
            return false
        }

        return arguments.contains(launchAppURL.path)
    }

    static func register() throws {
        try FileManager.default.createDirectory(
            at: plistURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let plist: [String: Any] = [
            "Label": label,
            "ProgramArguments": [
                "/usr/bin/open",
                "-n",
                launchAppURL.path
            ],
            "RunAtLoad": true
        ]

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )
        try data.write(to: plistURL, options: .atomic)
    }

    static func unregister() throws {
        guard FileManager.default.fileExists(atPath: plistURL.path) else {
            return
        }

        try FileManager.default.removeItem(at: plistURL)
    }
}
