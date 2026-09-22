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
    case update
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
        hasUpdateAvailable: Bool = false,
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
                accessibilityDescription: "Recny is recording"
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
                accessibilityDescription: "Recny error"
            )
        case .idle:
            if needsRecordingPermissions {
                return recordingPermissionsNeededState(
                    hasPlayableLastRecording: hasPlayableLastRecording,
                    hasLastRecording: hasLastRecording
                )
            }

            if hasUpdateAvailable {
                return MenuBarDisplayState(
                    recordingToggleTitle: "Start Recording",
                    recordingToggleAction: .start,
                    canPlayLastRecording: hasPlayableLastRecording,
                    canOpenLastRecordingFolder: hasLastRecording,
                    symbolName: "play.update",
                    statusItemTitle: "",
                    tint: .update,
                    accessibilityDescription: "Recny update available"
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
                accessibilityDescription: "Recny idle"
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
            accessibilityDescription: "Recny recording unavailable: permissions needed"
        )
    }
}
