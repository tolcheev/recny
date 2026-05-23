import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(CoreAudio)
import CoreAudio
#endif

public struct ActiveApplicationSnapshot: Equatable, Sendable {
    public let name: String
    public let bundleID: String

    public init(name: String, bundleID: String) {
        self.name = name
        self.bundleID = bundleID
    }
}

public struct AudioActivitySnapshot: Equatable, Sendable {
    public let microphoneActive: Bool
    public let systemAudioActive: Bool

    public init(microphoneActive: Bool, systemAudioActive: Bool) {
        self.microphoneActive = microphoneActive
        self.systemAudioActive = systemAudioActive
    }
}

public struct AutoStartSettings: Codable, Equatable, Sendable {
    public static let defaultWhitelist: [String] = [
        "Zoom",
        "Google Chrome",
        "Safari",
        "Firefox",
        "Yandex Browser",
        "Microsoft Edge",
        "Telegram",
        "Discord"
    ]

    public var isEnabled: Bool
    public var whitelist: [String]
    public var blacklist: [String]
    public var cooldownSeconds: TimeInterval
    public var minDetectionDurationSeconds: TimeInterval

    public init(
        isEnabled: Bool = true,
        whitelist: [String] = Self.defaultWhitelist,
        blacklist: [String] = [],
        cooldownSeconds: TimeInterval = 180,
        minDetectionDurationSeconds: TimeInterval = 20
    ) {
        self.isEnabled = isEnabled
        self.whitelist = whitelist
        self.blacklist = blacklist
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
    }
}

public enum AutoStartDecisionAction: Equatable, Sendable {
    case start
    case wait
    case ignore
}

public enum AutoStartDecisionReason: String, Equatable, Sendable {
    case startRecording = "start_recording"
    case waitingForMinDetectionDuration = "waiting_for_min_detection_duration"
    case disabled = "disabled"
    case noActiveApp = "no_active_app"
    case appNotWhitelisted = "app_not_whitelisted"
    case appBlacklisted = "app_blacklisted"
    case alreadyRecording = "already_recording"
    case cooldownActive = "cooldown_active"
    case microphoneInactive = "microphone_inactive"
    case systemAudioInactive = "system_audio_inactive"
}

public struct AutoStartDecision: Equatable, Sendable {
    public let action: AutoStartDecisionAction
    public let reason: AutoStartDecisionReason
    public let recordingSource: RecordingSource?
    public let message: String

    public init(
        action: AutoStartDecisionAction,
        reason: AutoStartDecisionReason,
        recordingSource: RecordingSource? = nil,
        message: String
    ) {
        self.action = action
        self.reason = reason
        self.recordingSource = recordingSource
        self.message = message
    }
}

public struct AutoStartEvaluationContext: Equatable, Sendable {
    public let activeApplication: ActiveApplicationSnapshot?
    public let audioActivity: AudioActivitySnapshot
    public let isAlreadyRecording: Bool
    public let lastStoppedAt: Date?
    public let now: Date

    public init(
        activeApplication: ActiveApplicationSnapshot?,
        audioActivity: AudioActivitySnapshot,
        isAlreadyRecording: Bool,
        lastStoppedAt: Date?,
        now: Date
    ) {
        self.activeApplication = activeApplication
        self.audioActivity = audioActivity
        self.isAlreadyRecording = isAlreadyRecording
        self.lastStoppedAt = lastStoppedAt
        self.now = now
    }
}

public struct AutoStartEngine: Sendable {
    private var candidate: Candidate?

    public init() {}

    public mutating func resetCandidate() {
        candidate = nil
    }

    public mutating func evaluate(
        _ context: AutoStartEvaluationContext,
        settings: AutoStartSettings
    ) -> AutoStartDecision {
        guard settings.isEnabled else {
            return ignore(.disabled, "Auto-start disabled")
        }

        guard let activeApplication = context.activeApplication else {
            return ignore(.noActiveApp, "No active app")
        }

        guard matches(activeApplication, entries: settings.whitelist) else {
            return ignore(.appNotWhitelisted, "\(activeApplication.name) is not whitelisted")
        }

        guard !matches(activeApplication, entries: settings.blacklist) else {
            return ignore(.appBlacklisted, "\(activeApplication.name) is blacklisted")
        }

        guard !context.isAlreadyRecording else {
            return ignore(.alreadyRecording, "Recording is already active")
        }

        if let lastStoppedAt = context.lastStoppedAt {
            let elapsed = context.now.timeIntervalSince(lastStoppedAt)
            guard elapsed >= settings.cooldownSeconds else {
                let remaining = max(0, settings.cooldownSeconds - elapsed)
                return ignore(.cooldownActive, "Cooldown active for \(Int(remaining.rounded(.up))) more seconds")
            }
        }

        guard context.audioActivity.microphoneActive else {
            return ignore(.microphoneInactive, "Microphone activity is not detected")
        }

        let knownCallApp = isKnownCallApp(activeApplication)
        guard context.audioActivity.systemAudioActive || knownCallApp else {
            return ignore(.systemAudioInactive, "System audio activity is not detected")
        }

        let key = candidateKey(for: activeApplication)
        if candidate?.key != key {
            candidate = Candidate(key: key, observedAt: context.now)
        }

        let observedAt = candidate?.observedAt ?? context.now
        let detectionDuration = context.now.timeIntervalSince(observedAt)
        guard detectionDuration >= settings.minDetectionDurationSeconds else {
            return AutoStartDecision(
                action: .wait,
                reason: .waitingForMinDetectionDuration,
                message: "Call signal observed for \(Int(detectionDuration)) seconds"
            )
        }

        candidate = nil
        return AutoStartDecision(
            action: .start,
            reason: .startRecording,
            recordingSource: RecordingSource(
                appName: activeApplication.name,
                bundleID: activeApplication.bundleID,
                trigger: "autostart",
                ruleID: "autostart.v1"
            ),
            message: "Auto-start conditions passed for \(activeApplication.name)"
        )
    }

    private mutating func ignore(_ reason: AutoStartDecisionReason, _ message: String) -> AutoStartDecision {
        candidate = nil
        return AutoStartDecision(action: .ignore, reason: reason, message: message)
    }

    private func matches(_ app: ActiveApplicationSnapshot, entries: [String]) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return entries.contains { entry in
            appTokens.contains(normalize(entry))
        }
    }

    private func isKnownCallApp(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return KnownApps.knownCallAppTokens.contains { token in
            appTokens.contains(normalize(token))
        }
    }

    private func candidateKey(for app: ActiveApplicationSnapshot) -> String {
        "\(normalize(app.bundleID))|\(normalize(app.name))"
    }

    private func tokens(for app: ActiveApplicationSnapshot) -> [String] {
        var tokens = [app.name, app.bundleID]
        tokens.append(contentsOf: KnownApps.bundleAliases[normalize(app.bundleID)] ?? [])
        return tokens.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private struct Candidate: Sendable {
        let key: String
        let observedAt: Date
    }
}

public protocol ActiveApplicationDetecting {
    func activeApplication() -> ActiveApplicationSnapshot?
}

public protocol AudioActivityDetecting {
    func audioActivity() -> AudioActivitySnapshot
}

#if canImport(AppKit)
public final class WorkspaceActiveApplicationDetector: ActiveApplicationDetecting {
    public init() {}

    public func activeApplication() -> ActiveApplicationSnapshot? {
        guard let application = NSWorkspace.shared.frontmostApplication else {
            return nil
        }

        return ActiveApplicationSnapshot(
            name: application.localizedName ?? application.bundleIdentifier ?? "Unknown",
            bundleID: application.bundleIdentifier ?? ""
        )
    }
}
#endif

#if canImport(CoreAudio)
public final class CoreAudioActivityDetector: AudioActivityDetecting {
    public init() {}

    public func audioActivity() -> AudioActivitySnapshot {
        AudioActivitySnapshot(
            microphoneActive: isDefaultDeviceRunning(selector: kAudioHardwarePropertyDefaultInputDevice),
            systemAudioActive: isDefaultDeviceRunning(selector: kAudioHardwarePropertyDefaultOutputDevice)
        )
    }

    private func isDefaultDeviceRunning(selector: AudioObjectPropertySelector) -> Bool {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &deviceID
        ) == noErr, deviceID != 0 else {
            return false
        }

        var running = UInt32(0)
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            deviceID,
            &address,
            0,
            nil,
            &size,
            &running
        ) == noErr else {
            return false
        }

        return running != 0
    }
}
#endif

public enum AutoStartSettingsStore {
    private static let key = "com.torbit.recorder.autostart.settings.v1"

    public static func load(defaults: UserDefaults = .standard) -> AutoStartSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AutoStartSettings.self, from: data)
        else {
            return AutoStartSettings()
        }

        return AutoStartSettings(
            isEnabled: settings.isEnabled,
            whitelist: settings.whitelist,
            blacklist: settings.blacklist,
            cooldownSeconds: settings.cooldownSeconds,
            minDetectionDurationSeconds: settings.minDetectionDurationSeconds
        )
    }

    public static func save(_ settings: AutoStartSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}

private enum KnownApps {
    static let bundleAliases: [String: [String]] = [
        "us.zoom.xos": ["Zoom", "zoom.us"],
        "com.google.chrome": ["Google Chrome"],
        "com.apple.safari": ["Safari"],
        "org.mozilla.firefox": ["Firefox"],
        "ru.yandex.desktop.yandex-browser": ["Yandex Browser"],
        "com.microsoft.edgemac": ["Microsoft Edge"],
        "ru.keepcoder.telegram": ["Telegram"],
        "org.telegram.desktop": ["Telegram"],
        "com.hnc.discord": ["Discord"]
    ]

    static let knownCallAppTokens: [String] = [
        "Zoom",
        "zoom.us",
        "us.zoom.xos",
        "Telegram",
        "ru.keepcoder.Telegram",
        "org.telegram.desktop",
        "Discord",
        "com.hnc.Discord"
    ]
}
