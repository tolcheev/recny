import AVFoundation
import CoreGraphics
import Foundation

public enum RecorderPermissionState: String, CaseIterable, Equatable, Sendable {
    case granted
    case missing
    case denied
    case notDetermined
    case restartRequired
    case unknown

    public var title: String {
        switch self {
        case .granted:
            return "Granted"
        case .missing:
            return "Missing"
        case .denied:
            return "Denied"
        case .notDetermined:
            return "Not determined"
        case .restartRequired:
            return "Restart required"
        case .unknown:
            return "Unknown"
        }
    }

    public var isBlocking: Bool {
        self != .granted
    }
}

public enum MicrophoneAuthorizationDisplayState: Equatable, Sendable {
    case authorized
    case notDetermined
    case denied
    case restricted
    case unknown
}

public struct RecorderPermissionSnapshot: Equatable, Sendable {
    public var microphone: RecorderPermissionState
    public var screenSystemAudio: RecorderPermissionState
    public var storage: RecorderPermissionState

    public init(
        microphone: RecorderPermissionState,
        screenSystemAudio: RecorderPermissionState,
        storage: RecorderPermissionState
    ) {
        self.microphone = microphone
        self.screenSystemAudio = screenSystemAudio
        self.storage = storage
    }

    public static var unknown: RecorderPermissionSnapshot {
        RecorderPermissionSnapshot(
            microphone: .unknown,
            screenSystemAudio: .unknown,
            storage: .unknown
        )
    }
}

public enum RecordingPermissionDisplay {
    public static func microphoneState(
        from authorization: MicrophoneAuthorizationDisplayState
    ) -> RecorderPermissionState {
        switch authorization {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied, .restricted:
            return .denied
        case .unknown:
            return .unknown
        }
    }

    public static func screenSystemAudioState(
        processGranted: Bool,
        settingsOpened: Bool,
        lastErrorMessage: String?
    ) -> RecorderPermissionState {
        if let lastErrorMessage,
           isDeniedScreenCaptureError(lastErrorMessage) {
            return processGranted || settingsOpened ? .restartRequired : .denied
        }

        if let lastErrorMessage,
           isRestartRequiredScreenCaptureError(lastErrorMessage) {
            return .restartRequired
        }

        guard !processGranted else {
            return .granted
        }

        if settingsOpened {
            return .restartRequired
        }

        return .missing
    }

    public static func storageState(isWritable: Bool) -> RecorderPermissionState {
        isWritable ? .granted : .denied
    }

    public static func canStartRecording(
        _ snapshot: RecorderPermissionSnapshot,
        systemAudioEnabled: Bool
    ) -> Bool {
        guard snapshot.microphone == .granted,
              snapshot.storage == .granted
        else {
            return false
        }

        guard systemAudioEnabled else {
            return true
        }

        return snapshot.screenSystemAudio == .granted
    }

    public static func blockingReason(
        _ snapshot: RecorderPermissionSnapshot,
        systemAudioEnabled: Bool
    ) -> String? {
        if snapshot.microphone != .granted {
            return "Microphone access is required before recording."
        }

        if systemAudioEnabled && snapshot.screenSystemAudio != .granted {
            if snapshot.screenSystemAudio == .restartRequired {
                return "Screen & System Audio Recording is enabled, but TOrbitRecorder must be restarted."
            }

            return "Screen & System Audio Recording access is required before recording."
        }

        if snapshot.storage != .granted {
            return "The recordings folder must be writable before recording."
        }

        return nil
    }

    public static func shouldShowOnboarding(
        _ snapshot: RecorderPermissionSnapshot,
        systemAudioEnabled: Bool
    ) -> Bool {
        !canStartRecording(snapshot, systemAudioEnabled: systemAudioEnabled)
    }

    private static func isDeniedScreenCaptureError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("declined")
            || lowered.contains("denied")
            || lowered.contains("отклонил")
            || lowered.contains("запрет")
    }

    private static func isRestartRequiredScreenCaptureError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("screen & system audio recording permission")
            || lowered.contains("scstreamerrordomain")
            || lowered.contains("code: -3801")
            || lowered.contains("перезап")
            || lowered.contains("restart")
    }
}

public protocol RecordingPermissionChecking {
    func snapshot(
        outputFolderURL: URL,
        screenSystemAudioSettingsOpened: Bool,
        lastErrorMessage: String?
    ) -> RecorderPermissionSnapshot
}

public final class SystemRecordingPermissionChecker: RecordingPermissionChecking {
    public init() {}

    public func snapshot(
        outputFolderURL: URL,
        screenSystemAudioSettingsOpened: Bool,
        lastErrorMessage: String?
    ) -> RecorderPermissionSnapshot {
        RecorderPermissionSnapshot(
            microphone: RecordingPermissionDisplay.microphoneState(
                from: Self.microphoneAuthorizationState()
            ),
            screenSystemAudio: RecordingPermissionDisplay.screenSystemAudioState(
                processGranted: CGPreflightScreenCaptureAccess(),
                settingsOpened: screenSystemAudioSettingsOpened,
                lastErrorMessage: lastErrorMessage
            ),
            storage: RecordingPermissionDisplay.storageState(
                isWritable: Self.isWritableDirectory(outputFolderURL)
            )
        )
    }

    private static func microphoneAuthorizationState() -> MicrophoneAuthorizationDisplayState {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return .authorized
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .unknown
        }
    }

    private static func isWritableDirectory(_ url: URL) -> Bool {
        do {
            try FileManager.default.createDirectory(
                at: url,
                withIntermediateDirectories: true
            )
            let testURL = url.appendingPathComponent(".torbit-permission-write-test")
            try Data().write(to: testURL, options: [.atomic])
            try? FileManager.default.removeItem(at: testURL)
            return true
        } catch {
            return false
        }
    }
}
