import Foundation
import TOrbitRecorderCore

enum AppUpdateEvents {
    static let updateAvailable = Notification.Name("com.torbit.recorder.update.available")
    static let updateDismissed = Notification.Name("com.torbit.recorder.update.dismissed")

    static func postAvailable(_ release: AppUpdateRelease) {
        NotificationCenter.default.post(name: updateAvailable, object: release)
    }

    static func postDismissed(version: String) {
        NotificationCenter.default.post(name: updateDismissed, object: version)
    }

    static func release(from notification: Notification) -> AppUpdateRelease? {
        notification.object as? AppUpdateRelease
    }

    static func dismissedVersion(from notification: Notification) -> String? {
        notification.object as? String
    }
}
