import Foundation

#if canImport(AppKit)
import AppKit
#endif

#if canImport(CoreGraphics)
import CoreGraphics
#endif

#if canImport(CoreAudio)
import CoreAudio
#endif

public struct ActiveApplicationSnapshot: Equatable, Sendable {
    public let name: String
    public let bundleID: String
    public let windowTitle: String?

    public init(name: String, bundleID: String, windowTitle: String? = nil) {
        self.name = name
        self.bundleID = bundleID
        self.windowTitle = windowTitle
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

public enum AutoStartMode: String, CaseIterable, Codable, Sendable {
    case off
    case askFirst = "ask_first"
    case auto
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
    public static let defaultBlacklistHints: [String] = [
        "Music",
        "Spotify",
        "VLC",
        "QuickTime Player",
        "TV"
    ]

    public var mode: AutoStartMode
    public var whitelist: [String]
    public var blacklist: [String]
    public var cooldownSeconds: TimeInterval
    public var minDetectionDurationSeconds: TimeInterval
    public var shortRecordingThresholdSeconds: TimeInterval

    public var isEnabled: Bool {
        get {
            mode != .off
        }
        set {
            mode = newValue ? .auto : .off
        }
    }

    public init(
        isEnabled: Bool = true,
        whitelist: [String] = Self.defaultWhitelist,
        blacklist: [String] = [],
        cooldownSeconds: TimeInterval = 180,
        minDetectionDurationSeconds: TimeInterval = 20,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds
    ) {
        self.mode = isEnabled ? .auto : .off
        self.whitelist = whitelist
        self.blacklist = blacklist
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
    }

    public init(
        mode: AutoStartMode,
        whitelist: [String] = Self.defaultWhitelist,
        blacklist: [String] = [],
        cooldownSeconds: TimeInterval = 180,
        minDetectionDurationSeconds: TimeInterval = 20,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds
    ) {
        self.mode = mode
        self.whitelist = whitelist
        self.blacklist = blacklist
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case isEnabled
        case whitelist
        case blacklist
        case cooldownSeconds
        case minDetectionDurationSeconds
        case shortRecordingThresholdSeconds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decodeIfPresent(AutoStartMode.self, forKey: .mode)
        let legacyIsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        self.mode = mode ?? (legacyIsEnabled ? .auto : .off)
        self.whitelist = try container.decodeIfPresent([String].self, forKey: .whitelist) ?? Self.defaultWhitelist
        self.blacklist = try container.decodeIfPresent([String].self, forKey: .blacklist) ?? []
        let cooldownSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .cooldownSeconds) ?? 180
        let minDetectionDurationSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .minDetectionDurationSeconds) ?? 20
        let shortRecordingThresholdSeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .shortRecordingThresholdSeconds) ?? TaggingStatus.shortRecordingThresholdSeconds
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(mode, forKey: .mode)
        try container.encode(isEnabled, forKey: .isEnabled)
        try container.encode(whitelist, forKey: .whitelist)
        try container.encode(blacklist, forKey: .blacklist)
        try container.encode(cooldownSeconds, forKey: .cooldownSeconds)
        try container.encode(minDetectionDurationSeconds, forKey: .minDetectionDurationSeconds)
        try container.encode(shortRecordingThresholdSeconds, forKey: .shortRecordingThresholdSeconds)
    }
}

public enum AutoStartDecisionAction: Equatable, Sendable {
    case start
    case ask
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
    case browserTitleNotCall = "browser_title_not_call"
}

public struct AutoStartDecision: Equatable, Sendable {
    public let action: AutoStartDecisionAction
    public let reason: AutoStartDecisionReason
    public let recordingSource: RecordingSource?
    public let message: String
    public let confidence: String

    public init(
        action: AutoStartDecisionAction,
        reason: AutoStartDecisionReason,
        recordingSource: RecordingSource? = nil,
        message: String,
        confidence: String = "low"
    ) {
        self.action = action
        self.reason = reason
        self.recordingSource = recordingSource
        self.message = message
        self.confidence = confidence
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
    private static let knownCallAppContinuationWindowSeconds: TimeInterval = 10 * 60

    private var candidate: Candidate?
    private var recentKnownCallApp: RecentKnownCallApp?

    public init() {}

    public mutating func resetCandidate() {
        candidate = nil
        recentKnownCallApp = nil
    }

    public mutating func evaluate(
        _ context: AutoStartEvaluationContext,
        settings: AutoStartSettings
    ) -> AutoStartDecision {
        guard settings.mode != .off else {
            return ignore(.disabled, "Auto-start disabled")
        }

        guard !context.isAlreadyRecording else {
            recentKnownCallApp = nil
            return ignore(.alreadyRecording, "Recording is already active")
        }

        if let lastStoppedAt = context.lastStoppedAt {
            let elapsed = context.now.timeIntervalSince(lastStoppedAt)
            guard elapsed >= settings.cooldownSeconds else {
                recentKnownCallApp = nil
                let remaining = max(0, settings.cooldownSeconds - elapsed)
                return ignore(.cooldownActive, "Cooldown active for \(Int(remaining.rounded(.up))) more seconds")
            }
        }

        guard let activeApplication = context.activeApplication else {
            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }
            return ignore(.noActiveApp, "No active app")
        }

        rememberKnownCallAppIfEligible(activeApplication, settings: settings, now: context.now)

        guard matches(activeApplication, entries: settings.whitelist) else {
            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }
            return ignore(.appNotWhitelisted, "\(activeApplication.name) is not whitelisted")
        }

        guard !matches(activeApplication, entries: settings.blacklist) else {
            return ignore(.appBlacklisted, "\(activeApplication.name) is blacklisted")
        }

        guard let signal = startSignal(for: activeApplication, audioActivity: context.audioActivity) else {
            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }

            if !context.audioActivity.microphoneActive {
                let title = activeApplication.windowTitle.map { " title=\($0)" } ?? ""
                return ignore(.microphoneInactive, "Microphone activity is not detected.\(title)")
            }

            if isBrowser(activeApplication), let title = activeApplication.windowTitle, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return ignore(.browserTitleNotCall, "Browser title does not look like a call: \(title)")
            }

            return ignore(.systemAudioInactive, "System audio activity is not detected")
        }

        if !signal.startsImmediately {
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
                    message: "Call signal observed for \(Int(detectionDuration)) seconds",
                    confidence: signal.confidence
                )
            }
        }

        candidate = nil
        recentKnownCallApp = nil
        return startDecision(for: activeApplication, signal: signal, settings: settings)
    }

    private func startDecision(
        for app: ActiveApplicationSnapshot,
        signal: AutoStartSignal,
        settings: AutoStartSettings
    ) -> AutoStartDecision {
        let source = RecordingSource(
            appName: app.name,
            bundleID: app.bundleID,
            trigger: "autostart",
            ruleID: signal.ruleID,
            confidence: signal.confidence,
            reason: signal.reason
        )
        return AutoStartDecision(
            action: settings.mode == .askFirst ? .ask : .start,
            reason: .startRecording,
            recordingSource: source,
            message: "\(signal.reason) app=\(app.name)",
            confidence: signal.confidence
        )
    }

    private mutating func rememberKnownCallAppIfEligible(
        _ app: ActiveApplicationSnapshot,
        settings: AutoStartSettings,
        now: Date
    ) {
        guard matches(app, entries: settings.whitelist),
              !matches(app, entries: settings.blacklist),
              isKnownCallApp(app)
        else {
            return
        }

        recentKnownCallApp = RecentKnownCallApp(application: app, observedAt: now)
    }

    private mutating func continuationDecision(
        _ context: AutoStartEvaluationContext,
        settings: AutoStartSettings
    ) -> AutoStartDecision? {
        guard let recentKnownCallApp = self.recentKnownCallApp else {
            return nil
        }

        let elapsed = context.now.timeIntervalSince(recentKnownCallApp.observedAt)
        guard elapsed <= Self.knownCallAppContinuationWindowSeconds else {
            self.recentKnownCallApp = nil
            return nil
        }

        let app = recentKnownCallApp.application
        guard matches(app, entries: settings.whitelist),
              !matches(app, entries: settings.blacklist),
              let signal = startSignal(
                for: app,
                audioActivity: context.audioActivity,
                recentlyActive: true
              ),
              signal.startsImmediately
        else {
            return nil
        }

        candidate = nil
        self.recentKnownCallApp = nil
        return startDecision(for: app, signal: signal, settings: settings)
    }

    private mutating func ignore(_ reason: AutoStartDecisionReason, _ message: String) -> AutoStartDecision {
        candidate = nil
        return AutoStartDecision(action: .ignore, reason: reason, message: message)
    }

    private func startSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot,
        recentlyActive: Bool = false
    ) -> AutoStartSignal? {
        if isKnownCallApp(app) {
            if isZoom(app), audioActivity.systemAudioActive {
                return AutoStartSignal(
                    ruleID: "autostart.v2.zoom",
                    confidence: "high",
                    reason: "Zoom \(recentlyActive ? "recently active" : "active") with system audio activity.",
                    startsImmediately: true
                )
            }

            guard audioActivity.microphoneActive else {
                return nil
            }

            return AutoStartSignal(
                ruleID: isZoom(app) ? "autostart.v2.zoom" : "autostart.v2.known_call_app",
                confidence: "high",
                reason: isZoom(app)
                    ? "Zoom active with microphone activity."
                    : "\(app.name) active with microphone activity."
            )
        }

        if isBrowser(app) {
            guard audioActivity.microphoneActive else {
                return nil
            }

            guard audioActivity.systemAudioActive else {
                return nil
            }

            if let title = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                guard titleLooksLikeCall(title) else {
                    return nil
                }

                return AutoStartSignal(
                    ruleID: "autostart.v2.browser_title",
                    confidence: "high",
                    reason: "Browser call detected from active window title."
                )
            }

            return AutoStartSignal(
                ruleID: "autostart.v2.browser_fallback",
                confidence: "medium",
                reason: "Browser call inferred from microphone and system audio activity."
            )
        }

        guard audioActivity.microphoneActive else {
            return nil
        }

        guard audioActivity.systemAudioActive else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.generic_whitelist",
            confidence: "medium",
            reason: "\(app.name) active with microphone and system audio activity."
        )
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

    private func isZoom(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return appTokens.contains("zoom") || appTokens.contains("zoom.us") || appTokens.contains("us.zoom.xos")
    }

    private func isBrowser(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return KnownApps.browserTokens.contains { token in
            appTokens.contains(normalize(token))
        }
    }

    private func titleLooksLikeCall(_ title: String) -> Bool {
        let normalizedTitle = normalize(title)
        return KnownApps.browserCallTitleTokens.contains { token in
            titleContainsCallToken(normalizedTitle, token: normalize(token))
        }
    }

    private func titleContainsCallToken(_ title: String, token: String) -> Bool {
        guard !token.isEmpty else {
            return false
        }

        if token.contains(" ") {
            return title.contains(token)
        }

        var searchRange = title.startIndex..<title.endIndex
        while let range = title.range(of: token, range: searchRange) {
            let startsAtBoundary = range.lowerBound == title.startIndex
                || !isWordCharacter(title[title.index(before: range.lowerBound)])
            let endsAtBoundary = range.upperBound == title.endIndex
                || !isWordCharacter(title[range.upperBound])

            if startsAtBoundary && endsAtBoundary {
                return true
            }

            searchRange = range.upperBound..<title.endIndex
        }

        return false
    }

    private func isWordCharacter(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { scalar in
            CharacterSet.alphanumerics.contains(scalar) || scalar == "_"
        }
    }

    private func candidateKey(for app: ActiveApplicationSnapshot) -> String {
        "\(normalize(app.bundleID))|\(normalize(app.name))|\(normalize(app.windowTitle ?? ""))"
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

    private struct RecentKnownCallApp: Sendable {
        let application: ActiveApplicationSnapshot
        let observedAt: Date
    }

    private struct AutoStartSignal: Sendable {
        let ruleID: String
        let confidence: String
        let reason: String
        var startsImmediately = false
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
            bundleID: application.bundleIdentifier ?? "",
            windowTitle: activeWindowTitle(for: application.processIdentifier)
        )
    }

    private func activeWindowTitle(for processID: pid_t) -> String? {
        #if canImport(CoreGraphics)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return nil
        }

        return windows.first { window in
            if let ownerPID = window[kCGWindowOwnerPID as String] as? Int {
                return pid_t(ownerPID) == processID
            }
            return false
        }?[kCGWindowName as String] as? String
        #else
        return nil
        #endif
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
            mode: settings.mode,
            whitelist: settings.whitelist,
            blacklist: settings.blacklist,
            cooldownSeconds: settings.cooldownSeconds,
            minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
            shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds
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

    static let browserTokens: [String] = [
        "Google Chrome",
        "com.google.Chrome",
        "Safari",
        "com.apple.Safari",
        "Firefox",
        "org.mozilla.firefox",
        "Yandex Browser",
        "ru.yandex.desktop.yandex-browser",
        "Microsoft Edge",
        "com.microsoft.edgemac"
    ]

    static let browserCallTitleTokens: [String] = [
        "Meet",
        "Zoom",
        "Teams",
        "KTalk",
        "МТС Линк",
        "SberJazz",
        "Встреча",
        "Собеседование",
        "Interview",
        "Call"
    ]
}
