import Testing
@testable import TOrbitRecorderCore

struct RecordingPermissionDisplayTests {
    @Test
    func mapsMicrophoneAuthorizationToUserFacingState() {
        #expect(RecordingPermissionDisplay.microphoneState(from: .authorized) == .granted)
        #expect(RecordingPermissionDisplay.microphoneState(from: .notDetermined) == .notDetermined)
        #expect(RecordingPermissionDisplay.microphoneState(from: .denied) == .denied)
        #expect(RecordingPermissionDisplay.microphoneState(from: .restricted) == .denied)
        #expect(RecordingPermissionDisplay.microphoneState(from: .unknown) == .unknown)
    }

    @Test
    func mapsScreenAudioRestartRequiredAfterSettingsVisit() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: false,
            settingsOpened: true,
            lastErrorMessage: nil
        )

        #expect(state == .restartRequired)
        #expect(state.title == "Restart required")
    }

    @Test
    func mapsScreenAudioMissingBeforeSettingsVisit() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: false,
            settingsOpened: false,
            lastErrorMessage: nil
        )

        #expect(state == .missing)
    }

    @Test
    func mapsScreenAudioDeclinedErrorToDenied() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: false,
            settingsOpened: false,
            lastErrorMessage: "The user declined ScreenCaptureKit permission"
        )

        #expect(state == .denied)
    }

    @Test
    func startRequiresRequiredPermissionsAndStorage() {
        #expect(
            RecordingPermissionDisplay.canStartRecording(
                RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .granted,
                    storage: .granted
                ),
                systemAudioEnabled: true
            )
        )

        #expect(
            !RecordingPermissionDisplay.canStartRecording(
                RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .missing,
                    storage: .granted
                ),
                systemAudioEnabled: true
            )
        )

        #expect(
            RecordingPermissionDisplay.canStartRecording(
                RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .missing,
                    storage: .granted
                ),
                systemAudioEnabled: false
            )
        )
    }
}
