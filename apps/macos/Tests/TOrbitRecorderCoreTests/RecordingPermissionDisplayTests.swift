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

        #expect(state == .notDetermined)
        #expect(state.title == "Not determined")
    }

    @Test
    func mapsScreenAudioNotDeterminedBeforeCaptureStart() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: false,
            settingsOpened: false,
            lastErrorMessage: nil
        )

        #expect(state == .notDetermined)
    }

    @Test
    func captureStartProbeGrantedMapsToGrantedSystemAudio() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: true,
            settingsOpened: false,
            lastErrorMessage: nil
        )

        #expect(state == .granted)
    }

    @Test
    func mapsCoreAudioDeclinedErrorToDenied() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: false,
            settingsOpened: false,
            lastErrorMessage: "Core Audio system audio access denied"
        )

        #expect(state == .denied)
    }

    @Test
    func captureStartProbeWinsOverStaleSystemAudioError() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: true,
            settingsOpened: false,
            lastErrorMessage: "Core Audio system audio access denied"
        )

        #expect(state == .granted)
    }

    @Test
    func captureStartProbeDoesNotTreatLegacyScreenCaptureKitErrorAsBlocking() {
        let state = RecordingPermissionDisplay.screenSystemAudioState(
            processGranted: true,
            settingsOpened: false,
            lastErrorMessage: "Screen & System Audio Recording permission is unavailable: Пользователь отклонил положения и условия захвата приложения, окна или дисплея (domain: com.apple.ScreenCaptureKit.SCStreamErrorDomain, code: -3801)"
        )

        #expect(state == .granted)
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
                    screenSystemAudio: .notDetermined,
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
            !RecordingPermissionDisplay.canStartRecording(
                RecorderPermissionSnapshot(
                    microphone: .granted,
                    screenSystemAudio: .denied,
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
        #expect(PermissionOnboardingFormatter.title(for: .screenSystemAudio) == "System audio")
        #expect(PermissionOnboardingFormatter.title(for: .storage) == "Output folder writable")

        #expect(
            PermissionOnboardingFormatter.explanation(
                for: .screenSystemAudio,
                state: .restartRequired
            ) == "Permission is enabled. Restart ToRec to apply it."
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
            ) == "Request System Audio Access"
        )
        #expect(
            PermissionOnboardingFormatter.actionTitle(
                for: .screenSystemAudio,
                state: .denied
            ) == "Open System Audio Settings"
        )
        #expect(
            PermissionOnboardingFormatter.explanation(
                for: .screenSystemAudio,
                state: .notDetermined
            ) == "Use Fix Permissions to request system audio access before recording. macOS calls this Screen & System Audio Recording, but ToRec records only audio, not screen video."
        )
        #expect(
            PermissionOnboardingFormatter.inlineActionTitle(
                for: .microphone,
                state: .notDetermined
            ) == nil
        )
        #expect(
            PermissionOnboardingFormatter.inlineActionTitle(
                for: .screenSystemAudio,
                state: .notDetermined
            ) == nil
        )
        #expect(
            PermissionOnboardingFormatter.inlineActionTitle(
                for: .screenSystemAudio,
                state: .denied
            ) == "Open System Audio Settings"
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
                bundlePath: "/Applications/ToRec.app"
            ).contains("open \"/Applications/ToRec.app\"")
        )
    }

    @Test
    func refocusesMainWindowAfterPermissionPrompts() {
        #expect(
            PermissionPromptSequencePolicy.shouldRefocusMainWindow(
                after: .microphone,
                next: .systemAudio
            )
        )
        #expect(
            PermissionPromptSequencePolicy.shouldRefocusMainWindow(
                after: .microphone,
                next: nil
            )
        )
        #expect(
            PermissionPromptSequencePolicy.shouldRefocusMainWindow(
                after: .systemAudio,
                next: nil
            )
        )
    }

    @Test
    func restartCommandWaitsForCurrentProcessToExitBeforeOpeningBundle() {
        let command = AppRestartCommand.shellCommand(
            currentProcessID: 12345,
            bundlePath: "/Applications/ToRec.app"
        )

        #expect(command.contains("while /bin/kill -0 12345"))
        #expect(command.contains("/usr/bin/open -n '/Applications/ToRec.app'"))
    }
}
