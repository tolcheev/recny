import Foundation
import Testing
@testable import RecnyCore

struct RecordingPreflightTests {
    @Test
    func systemAudioNotDeterminedBlocksPreflightBeforeStart() throws {
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

        #expect(throws: RecordingControllerError.preflightFailed("System audio access is required before recording.")) {
            try checker.validate(context)
        }
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

    @Test
    func airPodsOnlyInputBlocksPreflightWithExplicitMessage() {
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
                MicrophoneInputDevice(id: "airpods", name: "AirPods Pro")
            ],
            preferredMicrophoneDeviceID: nil,
            systemAudioCaptureAvailable: true,
            isRecordingActive: false
        )

        #expect(throws: RecordingControllerError.preflightFailed("AirPods/Bluetooth microphone is blocked for recording. Connect the MacBook or USB microphone.")) {
            try checker.validate(context)
        }
    }
}
