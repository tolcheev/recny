import Foundation

public enum MenuBarRecordingToggleAction: Equatable, Sendable {
    case start
    case stop
    case fixPermissions
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
    public let statusItemTitle: String
    public let tint: MenuBarTint
    public let accessibilityDescription: String

    public init(
        recordingToggleTitle: String,
        recordingToggleAction: MenuBarRecordingToggleAction,
        canPlayLastRecording: Bool,
        canOpenLastRecordingFolder: Bool,
        symbolName: String,
        statusItemTitle: String,
        tint: MenuBarTint,
        accessibilityDescription: String
    ) {
        self.recordingToggleTitle = recordingToggleTitle
        self.recordingToggleAction = recordingToggleAction
        self.canPlayLastRecording = canPlayLastRecording
        self.canOpenLastRecordingFolder = canOpenLastRecordingFolder
        self.symbolName = symbolName
        self.statusItemTitle = statusItemTitle
        self.tint = tint
        self.accessibilityDescription = accessibilityDescription
    }
}

public enum MenuBarDisplayStatePresenter {
    public static func state(
        recordingStatus: RecordingStatus,
        hasPlayableLastRecording: Bool,
        hasLastRecording: Bool,
        showRecordingIndicator: Bool,
        needsRecordingPermissions: Bool
    ) -> MenuBarDisplayState {
        switch recordingStatus {
        case .recording:
            return MenuBarDisplayState(
                recordingToggleTitle: "Stop Recording",
                recordingToggleAction: .stop,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: showRecordingIndicator ? "play.fill" : "play",
                statusItemTitle: "",
                tint: .none,
                accessibilityDescription: "ToRec is recording"
            )
        case .error:
            if needsRecordingPermissions {
                return recordingPermissionsNeededState(
                    hasPlayableLastRecording: hasPlayableLastRecording,
                    hasLastRecording: hasLastRecording
                )
            }

            return MenuBarDisplayState(
                recordingToggleTitle: "Start Recording",
                recordingToggleAction: .start,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: "play",
                statusItemTitle: "",
                tint: .none,
                accessibilityDescription: "ToRec error"
            )
        case .idle:
            if needsRecordingPermissions {
                return recordingPermissionsNeededState(
                    hasPlayableLastRecording: hasPlayableLastRecording,
                    hasLastRecording: hasLastRecording
                )
            }

            return MenuBarDisplayState(
                recordingToggleTitle: "Start Recording",
                recordingToggleAction: .start,
                canPlayLastRecording: hasPlayableLastRecording,
                canOpenLastRecordingFolder: hasLastRecording,
                symbolName: "play",
                statusItemTitle: "",
                tint: .none,
                accessibilityDescription: "ToRec idle"
            )
        }
    }

    private static func recordingPermissionsNeededState(
        hasPlayableLastRecording: Bool,
        hasLastRecording: Bool
    ) -> MenuBarDisplayState {
        MenuBarDisplayState(
            recordingToggleTitle: "Fix Recording Permissions",
            recordingToggleAction: .fixPermissions,
            canPlayLastRecording: hasPlayableLastRecording,
            canOpenLastRecordingFolder: hasLastRecording,
            symbolName: "permission.question",
            statusItemTitle: "",
            tint: .error,
            accessibilityDescription: "ToRec recording unavailable: permissions needed"
        )
    }
}
