import Foundation
import Testing
@testable import TOrbitRecorderCore

struct RecordingPreflightTests {
    @Test
    func requestableSystemAudioPermissionDoesNotBlockPreflight() throws {
        let checker = DefaultRecordingPreflightChecker(minimumFreeDiskSpaceBytes: 0)
        let context = RecordingPreflightContext(
            permissionSnapshot: RecorderPermissionSnapshot(
                microphone: .granted,
                screenSystemAudio: .notDetermined,
                storage: .granted
            ),
            systemAudioEnabled: true,
            outputFolderURL: URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true),
            availableMicrophoneDevices: [
                MicrophoneInputDevice(id: "builtin", name: "MacBook Pro Microphone")
            ],
            preferredMicrophoneDeviceID: nil,
            systemAudioCaptureAvailable: true,
            isRecordingActive: false
        )

        try checker.validate(context)
    }

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
