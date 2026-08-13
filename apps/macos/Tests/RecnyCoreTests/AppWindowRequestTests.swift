import Foundation
import Testing
@testable import RecnyCore

@Suite
struct AppWindowRequestTests {
    @Test
    func showMainWindowNotificationCarriesReason() {
        let notification = AppWindowRequest.showMainWindowNotification(
            reason: .permissionPromptCompleted
        )

        #expect(notification.name == AppWindowRequest.showMainWindowNotificationName)
        #expect(notification.userInfo?[AppWindowRequest.reasonUserInfoKey] as? String == "permission_prompt_completed")
    }
}
