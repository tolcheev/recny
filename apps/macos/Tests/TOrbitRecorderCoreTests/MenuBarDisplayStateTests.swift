import Testing
@testable import TOrbitRecorderCore

struct MenuBarDisplayStateTests {
    @Test
    func idleStateShowsStartActionAndTextFreeOutlinePlayIcon() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .idle,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: false,
            showRecordingIndicator: true,
            needsRecordingPermissions: false
        )

        #expect(state.recordingToggleTitle == "Start Recording")
        #expect(state.recordingToggleAction == .start)
        #expect(state.canPlayLastRecording == false)
        #expect(state.canOpenLastRecordingFolder == false)
        #expect(state.symbolName == "play")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "ToRec idle")
    }

    @Test
    func recordingStateShowsStopActionAndTextFreeFilledPlayIcon() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .recording,
            hasPlayableLastRecording: true,
            hasLastRecording: true,
            hasUpdateAvailable: false,
            showRecordingIndicator: true,
            needsRecordingPermissions: false
        )

        #expect(state.recordingToggleTitle == "Stop Recording")
        #expect(state.recordingToggleAction == .stop)
        #expect(state.canPlayLastRecording)
        #expect(state.canOpenLastRecordingFolder)
        #expect(state.symbolName == "play.fill")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "ToRec is recording")
    }

    @Test
    func recordingStateUsesTextFreeOutlinePlayIconWhenIndicatorDisabled() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .recording,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: false,
            showRecordingIndicator: false,
            needsRecordingPermissions: false
        )

        #expect(state.symbolName == "play")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "ToRec is recording")
    }

    @Test
    func errorStateKeepsTextFreeOutlinePlayIconAndStartAction() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .error,
            hasPlayableLastRecording: true,
            hasLastRecording: true,
            hasUpdateAvailable: false,
            showRecordingIndicator: true,
            needsRecordingPermissions: false
        )

        #expect(state.recordingToggleTitle == "Start Recording")
        #expect(state.recordingToggleAction == .start)
        #expect(state.canPlayLastRecording)
        #expect(state.canOpenLastRecordingFolder)
        #expect(state.symbolName == "play")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "ToRec error")
    }

    @Test
    func idleStateShowsOnlyPermissionQuestionIconWhenRecordingPermissionsAreMissing() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .idle,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: false,
            showRecordingIndicator: true,
            needsRecordingPermissions: true
        )

        #expect(state.recordingToggleTitle == "Fix Recording Permissions")
        #expect(state.recordingToggleAction == .fixPermissions)
        #expect(state.symbolName == "permission.question")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .error)
        #expect(state.accessibilityDescription == "ToRec recording unavailable: permissions needed")
    }

    @Test
    func errorStateShowsOnlyPermissionQuestionIconWhenRecordingPermissionsAreMissing() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .error,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: false,
            showRecordingIndicator: true,
            needsRecordingPermissions: true
        )

        #expect(state.recordingToggleTitle == "Fix Recording Permissions")
        #expect(state.recordingToggleAction == .fixPermissions)
        #expect(state.symbolName == "permission.question")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .error)
        #expect(state.accessibilityDescription == "ToRec recording unavailable: permissions needed")
    }

    @Test
    func recordingStateKeepsFilledPlayIconWhenRecordingPermissionsFlagIsStale() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .recording,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: true,
            showRecordingIndicator: true,
            needsRecordingPermissions: true
        )

        #expect(state.recordingToggleTitle == "Stop Recording")
        #expect(state.recordingToggleAction == .stop)
        #expect(state.symbolName == "play.fill")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "ToRec is recording")
    }

    @Test
    func idleUpdateAvailableShowsSubtleUpdateBadge() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .idle,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: true,
            showRecordingIndicator: true,
            needsRecordingPermissions: false
        )

        #expect(state.recordingToggleTitle == "Start Recording")
        #expect(state.recordingToggleAction == .start)
        #expect(state.symbolName == "play.update")
        #expect(state.statusItemTitle.isEmpty)
        #expect(state.tint == .update)
        #expect(state.accessibilityDescription == "ToRec update available")
    }

    @Test
    func permissionProblemTakesPriorityOverUpdateBadge() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .idle,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            hasUpdateAvailable: true,
            showRecordingIndicator: true,
            needsRecordingPermissions: true
        )

        #expect(state.recordingToggleTitle == "Fix Recording Permissions")
        #expect(state.symbolName == "permission.question")
        #expect(state.tint == .error)
        #expect(state.accessibilityDescription == "ToRec recording unavailable: permissions needed")
    }
}
