import Testing
@testable import TOrbitRecorderCore

struct MenuBarDisplayStateTests {
    @Test
    func idleStateShowsStartActionAndNeutralIcon() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .idle,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            showRecordingIndicator: true
        )

        #expect(state.recordingToggleTitle == "Start Recording")
        #expect(state.recordingToggleAction == .start)
        #expect(state.canPlayLastRecording == false)
        #expect(state.canOpenLastRecordingFolder == false)
        #expect(state.symbolName == "waveform.circle")
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "T-Orbit Recorder idle")
    }

    @Test
    func recordingStateShowsStopActionAndRecordingIcon() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .recording,
            hasPlayableLastRecording: true,
            hasLastRecording: true,
            showRecordingIndicator: true
        )

        #expect(state.recordingToggleTitle == "Stop Recording")
        #expect(state.recordingToggleAction == .stop)
        #expect(state.canPlayLastRecording)
        #expect(state.canOpenLastRecordingFolder)
        #expect(state.symbolName == "record.circle.fill")
        #expect(state.tint == .recording)
        #expect(state.accessibilityDescription == "T-Orbit Recorder is recording")
    }

    @Test
    func recordingStateStillShowsRecordingShapeWhenRedIndicatorDisabled() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .recording,
            hasPlayableLastRecording: false,
            hasLastRecording: false,
            showRecordingIndicator: false
        )

        #expect(state.symbolName == "record.circle.fill")
        #expect(state.tint == .none)
        #expect(state.accessibilityDescription == "T-Orbit Recorder is recording")
    }

    @Test
    func errorStateShowsErrorIconAndKeepsStartAction() {
        let state = MenuBarDisplayStatePresenter.state(
            recordingStatus: .error,
            hasPlayableLastRecording: true,
            hasLastRecording: true,
            showRecordingIndicator: true
        )

        #expect(state.recordingToggleTitle == "Start Recording")
        #expect(state.recordingToggleAction == .start)
        #expect(state.canPlayLastRecording)
        #expect(state.canOpenLastRecordingFolder)
        #expect(state.symbolName == "exclamationmark.triangle.fill")
        #expect(state.tint == .error)
        #expect(state.accessibilityDescription == "T-Orbit Recorder error")
    }
}
