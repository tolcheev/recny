import Testing
@testable import RecnyCore

struct MainRecorderLayoutPolicyTests {
    @Test
    func permissionOnboardingUsesScrollableContentWithFixedFooter() {
        let policy = MainRecorderLayoutPolicy(
            showsPermissionChecklist: true,
            hasUpdateBanner: false
        )

        #expect(policy.usesScrollableMainContent)
        #expect(policy.keepsFooterOutsideMainScroll)
        #expect(policy.minimumWindowHeight <= 560)
        #expect(policy.minimumScrollableContentHeight >= 260)
    }

    @Test
    func normalRecorderKeepsCompactWindowHeight() {
        let policy = MainRecorderLayoutPolicy(
            showsPermissionChecklist: false,
            hasUpdateBanner: false
        )

        #expect(!policy.usesScrollableMainContent)
        #expect(policy.keepsFooterOutsideMainScroll)
        #expect(policy.minimumWindowHeight <= 380)
    }

    @Test
    func permissionOnboardingSuppressesDuplicateIdleStatusCard() {
        let policy = MainRecorderLayoutPolicy(
            showsPermissionChecklist: true,
            hasUpdateBanner: false,
            status: .idle
        )

        #expect(!policy.showsRecordingStatusCard)
    }

    @Test
    func activeRecordingStillShowsStatusCardWhenPermissionChecklistIsVisible() {
        let policy = MainRecorderLayoutPolicy(
            showsPermissionChecklist: true,
            hasUpdateBanner: false,
            status: .recording
        )

        #expect(policy.showsRecordingStatusCard)
    }
}
