import Foundation
import Testing
@testable import TOrbitRecorderCore

struct RecordingPreflightTests {
    @Test
    func systemAudioUnavailableBlocksPreflightWhenSystemAudioIsEnabled() {
        let checker = DefaultRecordingPreflightChecker(minimumFreeDiskSpaceBytes: 0)
        let context = RecordingPreflightContext(
            permissionSnapshot: RecorderPermissionSnapshot(
                microphone: .granted,
                screenSystemAudio: .granted,
                storage: .granted
            ),
            systemAudioEnabled: true,
            outputFolderURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            availableMicrophoneDevices: [
                MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
            ],
            preferredMicrophoneDeviceID: nil,
            systemAudioCaptureAvailable: false,
            isRecordingActive: false
        )

        #expect(throws: RecordingControllerError.preflightFailed("System audio capture is not available on this Mac.")) {
            try checker.validate(context)
        }
    }
}
