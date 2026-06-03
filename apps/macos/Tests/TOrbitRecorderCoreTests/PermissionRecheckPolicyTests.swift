import Testing
@testable import TOrbitRecorderCore

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
