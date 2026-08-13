import Testing
@testable import RecnyCore

struct PermissionRecheckPolicyTests {
    @Test
    func normalFixPermissionsDoesNotInvalidateVerifiedSystemAudioCache() {
        #expect(
            !PermissionRecheckPolicy.shouldInvalidateSystemAudioProbeCache(
                mode: .normal,
                systemAudioEnabled: true
            )
        )
    }

    @Test
    func diagnosticsForceRecheckCanInvalidateVerifiedSystemAudioCache() {
        #expect(
            PermissionRecheckPolicy.shouldInvalidateSystemAudioProbeCache(
                mode: .forced,
                systemAudioEnabled: true
            )
        )
    }

    @Test
    func disabledSystemAudioNeverInvalidatesProbeCache() {
        #expect(
            !PermissionRecheckPolicy.shouldInvalidateSystemAudioProbeCache(
                mode: .forced,
                systemAudioEnabled: false
            )
        )
    }
}
