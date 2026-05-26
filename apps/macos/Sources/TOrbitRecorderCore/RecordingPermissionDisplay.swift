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
           isDeniedSystemAudioError(lastErrorMessage) {
            return processGranted || settingsOpened ? .restartRequired : .denied
        }

        if let lastErrorMessage,
           isRestartRequiredSystemAudioError(lastErrorMessage) {
            return .restartRequired
        }

        // CGPreflightScreenCaptureAccess can be true while Core Audio process-tap
        // system audio permission has not been requested yet. Treat the raw
        // preflight signal as advisory only; AppState promotes this state to
        // granted after the explicit Core Audio permission probe succeeds.
        _ = processGranted
        return .notDetermined
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

        return !isSystemAudioPermissionBlocking(snapshot.screenSystemAudio)
    }

    public static func blockingReason(
        _ snapshot: RecorderPermissionSnapshot,
        systemAudioEnabled: Bool
    ) -> String? {
        if snapshot.microphone != .granted {
            return "Microphone access is required before recording."
        }

        if systemAudioEnabled && isSystemAudioPermissionBlocking(snapshot.screenSystemAudio) {
            if snapshot.screenSystemAudio == .restartRequired {
                return "System audio access is enabled, but T-Orbit Recorder must be restarted."
            }

            return "System audio access is required before recording."
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

    private static func isDeniedSystemAudioError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("core audio system audio access denied")
            || lowered.contains("audiohardwarecreateprocesstap")
    }

    private static func isRestartRequiredSystemAudioError(_ message: String) -> Bool {
        let lowered = message.lowercased()
        return lowered.contains("system audio permission needs app restart")
    }

    private static func isSystemAudioPermissionBlocking(_ state: RecorderPermissionState) -> Bool {
        switch state {
        case .denied, .missing, .notDetermined, .restartRequired, .unknown:
            return true
        case .granted:
            return false
        }
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
