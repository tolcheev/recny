import Foundation

public enum MenuBarRecordingToggleAction: Equatable, Sendable {
    case start
    case stop
}

public enum MenuBarTint: Equatable, Sendable {
    case none
    case recording
    case error
}

public struct MenuBarDisplayState: Equatable, Sendable {
    public let recordingToggleTitle: String
    public let recordingToggleAction: MenuBarRecordingToggleAction
    public let canPlayLastRecording: Bool
    public let canOpenLastRecordingFolder: Bool
    public let symbolName: String
    public let tint: MenuBarTint
    public let accessibilityDescription: String

    public init(
        recordingToggleTitle: String,
        recordingToggleAction: MenuBarRecordingToggleAction,
        canPlayLastRecording: Bool,
        canOpenLastRecordingFolder: Bool,
        symbolName: String,
        tint: MenuBarTint,
        accessibilityDescription: String
    ) {
        self.recordingToggleTitle = recordingToggleTitle
        self.recordingToggleAction = recordingToggleAction
        self.canPlayLastRecording = canPlayLastRecording
        self.canOpenLastRecordingFolder = canOpenLastRecordingFolder
        self.symbolName = symbolName
        self.tint = tint
        self.accessibilityDescription = accessibilityDescription
    }
}

public enum MenuBarDisplayStatePresenter {
    public static func state(
        recordingStatus: RecordingStatus,
        hasPlayableLastRecording: Bool,
        hasLastRecording: Bool,
        showRecordingIndicator: Bool
    ) -> MenuBarDisplayState {
        switch recordingStatus {
        case .recording:
            return MenuBarDisplayState(
                recordingToggleTitle: "Stop Recording",
                recordingToggleAction: .stop,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: "record.circle.fill",
                tint: showRecordingIndicator ? .recording : .none,
                accessibilityDescription: "TOrbit Recorder is recording"
            )
        case .error:
            return MenuBarDisplayState(
                recordingToggleTitle: "Start Recording",
                recordingToggleAction: .start,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: "exclamationmark.circle.fill",
                tint: .error,
                accessibilityDescription: "TOrbit Recorder error"
            )
        case .idle:
            return MenuBarDisplayState(
                recordingToggleTitle: "Start Recording",
                recordingToggleAction: .start,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: "record.circle",
                tint: .none,
                accessibilityDescription: "TOrbit Recorder idle"
            )
        }
    }
}
