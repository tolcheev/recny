import Foundation

public enum AppWindowRequest {
    public static let showMainWindowNotificationName = Notification.Name(
        "com.torbit.recorder.show-main-window"
    )
    public static let reasonUserInfoKey = "reason"

    public enum Reason: String {
        case permissionPromptCompleted = "permission_prompt_completed"
    }

    public static func showMainWindowNotification(reason: Reason) -> Notification {
        Notification(
            name: showMainWindowNotificationName,
            object: nil,
            userInfo: [reasonUserInfoKey: reason.rawValue]
        )
    }

    public static func postShowMainWindow(reason: Reason) {
        NotificationCenter.default.post(showMainWindowNotification(reason: reason))
    }
}
