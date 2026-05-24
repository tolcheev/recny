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
    func screenCaptureKitPermissionErrorOverridesPreflightGrant() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: true,
            settingsOpened: false,
            lastErrorMessage: "Screen & System Audio Recording permission is unavailable: Пользователь отклонил положения и условия захвата приложения, окна или дисплея (domain: com.apple.ScreenCaptureKit.SCStreamErrorDomain, code: -3801)"
        )

        #expect(state == .restartRequired)
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

    @Test
    func formatsPermissionOnboardingRows() {
        #expect(PermissionOnboardingFormatter.title(for: .microphone) == "Microphone")
        #expect(PermissionOnboardingFormatter.title(for: .screenSystemAudio) == "Screen & System Audio Recording")
        #expect(PermissionOnboardingFormatter.title(for: .storage) == "Output folder writable")

        #expect(
            PermissionOnboardingFormatter.explanation(
                for: .screenSystemAudio,
                state: .restartRequired
            ) == "Permission is enabled. Restart TOrbitRecorder to apply it."
        )
        #expect(
            PermissionOnboardingFormatter.actionTitle(
                for: .microphone,
                state: .notDetermined
            ) == "Request Microphone Access"
        )
        #expect(
            PermissionOnboardingFormatter.actionTitle(
                for: .microphone,
                state: .denied
            ) == "Open Microphone Settings"
        )
        #expect(
            PermissionOnboardingFormatter.actionTitle(
                for: .screenSystemAudio,
                state: .missing
            ) == "Open Screen & System Audio Recording Settings"
        )
    }

    @Test
    func formatsRestartInstructionForSameBundle() {
        let snapshot = RecorderPermissionSnapshot(
            microphone: .granted,
            screenSystemAudio: .restartRequired,
            storage: .granted
        )

        #expect(PermissionOnboardingFormatter.requiresRestart(snapshot))
        #expect(
            PermissionOnboardingFormatter.reopenInstruction(
                bundlePath: "/Applications/TOrbitRecorder.app"
            ).contains("open \"/Applications/TOrbitRecorder.app\"")
        )
    }
}
