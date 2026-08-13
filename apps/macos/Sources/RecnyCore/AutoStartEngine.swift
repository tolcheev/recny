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
    public let processActivities: [AudioProcessActivitySnapshot]
    public let processActivityAvailable: Bool

    public init(
        microphoneActive: Bool,
        systemAudioActive: Bool,
        processActivities: [AudioProcessActivitySnapshot] = [],
        processActivityAvailable: Bool? = nil
    ) {
        self.microphoneActive = microphoneActive
        self.systemAudioActive = systemAudioActive
        self.processActivities = processActivities
        self.processActivityAvailable = processActivityAvailable ?? !processActivities.isEmpty
    }
}

public struct AudioProcessActivitySnapshot: Equatable, Sendable {
    public let processID: Int32
    public let bundleID: String
    public let isRunningInput: Bool
    public let isRunningOutput: Bool

    public init(
        processID: Int32,
        bundleID: String,
        isRunningInput: Bool,
        isRunningOutput: Bool
    ) {
        self.processID = processID
        self.bundleID = bundleID
        self.isRunningInput = isRunningInput
        self.isRunningOutput = isRunningOutput
    }

    public var isRunningAudio: Bool {
        isRunningInput || isRunningOutput
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
        "ChatGPT Atlas",
        "Microsoft Teams",
        "Yandex Telemost"
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
    public var autoStopDelaySeconds: TimeInterval

    /// User-selectable grace period before an auto-started recording is
    /// stopped after the call-active signal is lost. Constrained to the
    /// values shown in Settings to avoid hand-edited corner cases.
    public static let allowedAutoStopDelays: [TimeInterval] = [10, 30, 60]
    public static let defaultAutoStopDelaySeconds: TimeInterval = 10
    private static let legacyDefaultWhitelists: [[String]] = [
        [
            "Zoom",
            "Google Chrome",
            "Safari",
            "Firefox",
            "Yandex Browser",
            "Microsoft Edge",
            "Telegram",
            "Discord"
        ]
    ]
    private static let removedDefaultWhitelistEntries: [String] = [
        "Telegram",
        "Discord"
    ]

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
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds,
        autoStopDelaySeconds: TimeInterval = AutoStartSettings.defaultAutoStopDelaySeconds
    ) {
        self.mode = isEnabled ? .auto : .off
        self.whitelist = whitelist
        self.blacklist = blacklist
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
        self.autoStopDelaySeconds = Self.normalizeAutoStopDelay(autoStopDelaySeconds)
    }

    public init(
        mode: AutoStartMode,
        whitelist: [String] = Self.defaultWhitelist,
        blacklist: [String] = [],
        cooldownSeconds: TimeInterval = 180,
        minDetectionDurationSeconds: TimeInterval = 20,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds,
        autoStopDelaySeconds: TimeInterval = AutoStartSettings.defaultAutoStopDelaySeconds
    ) {
        self.mode = mode
        self.whitelist = whitelist
        self.blacklist = blacklist
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
        self.autoStopDelaySeconds = Self.normalizeAutoStopDelay(autoStopDelaySeconds)
    }

    enum CodingKeys: String, CodingKey {
        case mode
        case isEnabled
        case whitelist
        case blacklist
        case cooldownSeconds
        case minDetectionDurationSeconds
        case shortRecordingThresholdSeconds
        case autoStopDelaySeconds
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
        let autoStopDelaySeconds = try container.decodeIfPresent(TimeInterval.self, forKey: .autoStopDelaySeconds) ?? Self.defaultAutoStopDelaySeconds
        self.cooldownSeconds = max(0, cooldownSeconds)
        self.minDetectionDurationSeconds = min(30, max(15, minDetectionDurationSeconds))
        self.shortRecordingThresholdSeconds = min(300, max(15, shortRecordingThresholdSeconds))
        self.autoStopDelaySeconds = Self.normalizeAutoStopDelay(autoStopDelaySeconds)
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
        try container.encode(autoStopDelaySeconds, forKey: .autoStopDelaySeconds)
    }

    /// Snaps an arbitrary delay value to the nearest entry in
    /// `allowedAutoStopDelays`, defending against migrated/legacy values.
    public static func normalizeAutoStopDelay(_ value: TimeInterval) -> TimeInterval {
        guard let nearest = allowedAutoStopDelays.min(by: {
            abs($0 - value) < abs($1 - value)
        }) else {
            return defaultAutoStopDelaySeconds
        }
        return nearest
    }

    public static func whitelistMigratingKnownDefaultAdditions(_ whitelist: [String]) -> [String] {
        let normalizedWhitelist = normalizedSet(whitelist)
        let shouldMigrateLegacyDefault = legacyDefaultWhitelists.contains { legacy in
            normalizedWhitelist.isSuperset(of: normalizedSet(legacy))
        }
        guard shouldMigrateLegacyDefault else {
            return whitelist
        }

        let removedEntries = normalizedSet(removedDefaultWhitelistEntries)
        var migrated = whitelist.filter { entry in
            !removedEntries.contains(normalize(entry))
        }
        var normalizedMigrated = normalizedSet(migrated)
        for entry in defaultWhitelist where !normalizedMigrated.contains(normalize(entry)) {
            migrated.append(entry)
            normalizedMigrated.insert(normalize(entry))
        }
        return migrated
    }

    private static func normalizedSet(_ values: [String]) -> Set<String> {
        Set(values.map(normalize))
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
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
    case processAudioInactive = "process_audio_inactive"
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
    public let runningApplications: [ActiveApplicationSnapshot]
    public let audioActivity: AudioActivitySnapshot
    public let isAlreadyRecording: Bool
    public let lastStoppedAt: Date?
    public let now: Date

    public init(
        activeApplication: ActiveApplicationSnapshot?,
        runningApplications: [ActiveApplicationSnapshot] = [],
        audioActivity: AudioActivitySnapshot,
        isAlreadyRecording: Bool,
        lastStoppedAt: Date?,
        now: Date
    ) {
        self.activeApplication = activeApplication
        self.runningApplications = runningApplications
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
            if let runningDecision = runningKnownCallAppDecision(context, settings: settings) {
                return runningDecision
            }
            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }
            return ignore(.noActiveApp, "No active app")
        }

        rememberKnownCallAppIfEligible(activeApplication, settings: settings, now: context.now)

        guard matches(activeApplication, entries: settings.whitelist) else {
            if let runningDecision = runningKnownCallAppDecision(context, settings: settings) {
                return runningDecision
            }
            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }
            return ignore(.appNotWhitelisted, "\(activeApplication.name) is not whitelisted")
        }

        guard !matches(activeApplication, entries: settings.blacklist) else {
            return ignore(.appBlacklisted, "\(activeApplication.name) is blacklisted")
        }

        if let runningDecision = runningKnownCallAppDecision(context, settings: settings) {
            return runningDecision
        }

        guard let signal = startSignal(for: activeApplication, audioActivity: context.audioActivity) else {
            if let runningDecision = runningKnownCallAppDecision(context, settings: settings) {
                return runningDecision
            }

            if let continuation = continuationDecision(context, settings: settings) {
                return continuation
            }

            if !context.audioActivity.microphoneActive {
                return ignore(.microphoneInactive, "Microphone activity is not detected.")
            }

            if isBrowser(activeApplication) {
                guard context.audioActivity.systemAudioActive else {
                    return ignore(.systemAudioInactive, "System audio activity is not detected")
                }

                return ignore(.browserTitleNotCall, "Browser window title is unavailable or does not look like a call.")
            }

            if isGenericKnownCallApp(activeApplication) {
                guard context.audioActivity.systemAudioActive else {
                    return ignore(.systemAudioInactive, "System audio activity is not detected")
                }

                return ignore(
                    .processAudioInactive,
                    "\(sourceAppName(for: activeApplication)) process input/output activity is not detected."
                )
            }

            if isTelemost(activeApplication) {
                return ignore(
                    .processAudioInactive,
                    "Yandex Telemost call window or process input activity is not detected."
                )
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
            appName: sourceAppName(for: app),
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

    private mutating func runningKnownCallAppDecision(
        _ context: AutoStartEvaluationContext,
        settings: AutoStartSettings
    ) -> AutoStartDecision? {
        guard let app = preferredRunningKnownCallApp(context.runningApplications, settings: settings),
              let signal = backgroundStartSignal(for: app, audioActivity: context.audioActivity)
        else {
            return nil
        }

        if !signal.startsImmediately {
            let key = candidateKey(for: app)
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
        return startDecision(for: app, signal: signal, settings: settings)
    }

    private mutating func ignore(_ reason: AutoStartDecisionReason, _ message: String) -> AutoStartDecision {
        candidate = nil
        return AutoStartDecision(action: .ignore, reason: reason, message: message)
    }

    private func preferredRunningKnownCallApp(
        _ apps: [ActiveApplicationSnapshot],
        settings: AutoStartSettings
    ) -> ActiveApplicationSnapshot? {
        apps.first { app in
            matches(app, entries: settings.whitelist)
                && !matches(app, entries: settings.blacklist)
                && (
                    (isKnownCallApp(app) && (isZoom(app) || isTeams(app) || isTelemost(app)))
                    || isBrowserZoomWebCall(app)
                )
        }
    }

    private func backgroundStartSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        if isZoom(app) {
            if let signal = zoomProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if audioActivity.processActivityAvailable {
                return nil
            }

            guard audioActivity.microphoneActive else {
                return nil
            }

            if meetingWindowLooksActive(app) == true {
                return AutoStartSignal(
                    ruleID: "autostart.v2.zoom",
                    confidence: "high",
                    reason: "Zoom meeting window detected with microphone activity.",
                    startsImmediately: true
                )
            }

            guard audioActivity.systemAudioActive else {
                return nil
            }

            return AutoStartSignal(
                ruleID: "autostart.v2.zoom",
                confidence: "high",
                reason: "Zoom call detected with microphone and system audio activity.",
                startsImmediately: true
            )
        }

        if isTeams(app) {
            if let signal = teamsMeetingWindowSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = teamsProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }
        }

        if isTelemost(app) {
            if let signal = telemostProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = telemostMeetingWindowSignal(for: app, audioActivity: audioActivity) {
                return signal
            }
        }

        if isBrowser(app),
           audioActivity.systemAudioActive,
           let title = browserWindowTitle(for: app),
           titleLooksLikeZoomWebCall(title) {
            return AutoStartSignal(
                ruleID: "autostart.v2.browser_zoom_web_title",
                confidence: "high",
                reason: "Zoom Web detected from active browser title and system audio activity."
            )
        }

        return nil
    }

    private func startSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot,
        recentlyActive: Bool = false
    ) -> AutoStartSignal? {
        if isKnownCallApp(app) {
            if let signal = zoomProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = teamsMeetingWindowSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = teamsProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = telemostProcessAudioSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if let signal = telemostMeetingWindowSignal(for: app, audioActivity: audioActivity) {
                return signal
            }

            if isTelemost(app) {
                return nil
            }

            if isGenericKnownCallApp(app) {
                return genericKnownCallAppProcessAudioSignal(for: app, audioActivity: audioActivity)
            }

            if isZoom(app), audioActivity.processActivityAvailable {
                return nil
            }

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

            if !isZoom(app) {
                guard audioActivity.systemAudioActive else {
                    return nil
                }
            }

            return AutoStartSignal(
                ruleID: isZoom(app) ? "autostart.v2.zoom" : "autostart.v2.known_call_app",
                confidence: "high",
                reason: isZoom(app)
                    ? "Zoom active with microphone activity."
                    : "\(app.name) active with microphone and system audio activity."
            )
        }

        if isBrowser(app) {
            if !audioActivity.microphoneActive,
               audioActivity.systemAudioActive,
               let title = browserWindowTitle(for: app),
               titleLooksLikeZoomWebCall(title) {
                return AutoStartSignal(
                    ruleID: "autostart.v2.browser_zoom_web_title",
                    confidence: "high",
                    reason: "Zoom Web detected from active browser title and system audio activity."
                )
            }

            guard audioActivity.microphoneActive else {
                return nil
            }

            guard audioActivity.systemAudioActive else {
                return nil
            }

            if let title = browserWindowTitle(for: app) {
                guard titleLooksLikeCall(title) else {
                    return nil
                }

                return AutoStartSignal(
                    ruleID: "autostart.v2.browser_title",
                    confidence: "high",
                    reason: "Browser call detected from active window title."
                )
            }

            return nil
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

    private func isTeams(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return appTokens.contains("microsoft teams")
            || appTokens.contains("teams")
            || appTokens.contains("com.microsoft.teams")
            || appTokens.contains("com.microsoft.teams2")
    }

    private func isTelemost(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return appTokens.contains("yandex telemost")
            || appTokens.contains("telemost")
            || appTokens.contains("яндекс телемост")
            || appTokens.contains("телемост")
            || appTokens.contains("ru.yandex.desktop.telemost")
    }

    private func isBrowser(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return KnownApps.browserTokens.contains { token in
            appTokens.contains(normalize(token))
        }
    }

    private func isBrowserZoomWebCall(_ app: ActiveApplicationSnapshot) -> Bool {
        guard isBrowser(app),
              let title = browserWindowTitle(for: app)
        else {
            return false
        }

        return titleLooksLikeZoomWebCall(title)
    }

    private func titleLooksLikeCall(_ title: String) -> Bool {
        let normalizedTitle = normalize(title)
        return KnownApps.browserCallTitleTokens.contains { token in
            titleContainsCallToken(normalizedTitle, token: normalize(token))
        }
    }

    private func titleLooksLikeZoomWebCall(_ title: String) -> Bool {
        let normalizedTitle = normalize(title)
        return KnownApps.browserZoomWebTitleTokens.contains { token in
            titleContainsCallToken(normalizedTitle, token: normalize(token))
        }
    }

    private func browserWindowTitle(for app: ActiveApplicationSnapshot) -> String? {
        guard let title = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            return nil
        }

        return title
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

    private func sourceAppName(for app: ActiveApplicationSnapshot) -> String {
        if isZoom(app) {
            return "Zoom"
        }

        if isTeams(app) {
            return "Microsoft Teams"
        }

        if isTelemost(app) {
            return "Yandex Telemost"
        }

        if isTelegram(app) {
            return "Telegram"
        }

        if isDiscord(app) {
            return "Discord"
        }

        return app.name
    }

    private func zoomProcessAudioSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard isZoom(app),
              zoomProcessAudioIsActive(audioActivity)
        else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.zoom_process_audio",
            confidence: "high",
            reason: "Zoom process is using audio.",
            startsImmediately: true
        )
    }

    private func zoomProcessAudioIsActive(_ audioActivity: AudioActivitySnapshot) -> Bool {
        audioActivity.processActivities.contains { activity in
            isZoomBundleID(activity.bundleID) && activity.isRunningAudio
        }
    }

    private func isZoomBundleID(_ value: String) -> Bool {
        let normalizedValue = normalize(value)
        return normalizedValue == "us.zoom.xos"
            || normalizedValue == "zoom.us"
            || normalizedValue == "zoom"
            || normalizedValue.hasPrefix("us.zoom.")
            || normalizedValue.contains(".zoom.")
    }

    private func meetingWindowLooksActive(_ app: ActiveApplicationSnapshot) -> Bool? {
        guard let title = app.windowTitle?.trimmingCharacters(in: .whitespacesAndNewlines),
              !title.isEmpty
        else {
            return nil
        }

        let normalizedTitle = title.lowercased()
        return normalizedTitle.contains("meeting")
            || normalizedTitle.contains("conference")
            || normalizedTitle.contains("конференц")
            || normalizedTitle.contains("встреч")
            || normalizedTitle.contains("waiting room")
            || normalizedTitle.contains("зал ожидания")
            || normalizedTitle.contains("participants")
            || normalizedTitle.contains("участник")
            || normalizedTitle.contains("share screen")
            || normalizedTitle.contains("поделиться")
    }

    private func teamsMeetingWindowSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard isTeams(app),
              audioActivity.microphoneActive,
              meetingWindowLooksActive(app) == true
        else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.teams_meeting_window",
            confidence: "high",
            reason: "Microsoft Teams meeting window detected with microphone activity.",
            startsImmediately: true
        )
    }

    private func teamsProcessAudioSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard isTeams(app),
              teamsProcessAudioIsActive(audioActivity)
        else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.teams_process_audio",
            confidence: "high",
            reason: "Microsoft Teams process is using audio.",
            startsImmediately: true
        )
    }

    private func teamsProcessAudioIsActive(_ audioActivity: AudioActivitySnapshot) -> Bool {
        audioActivity.processActivities.contains { activity in
            isTeamsBundleID(activity.bundleID) && activity.isRunningAudio
        }
    }

    private func isTeamsBundleID(_ value: String) -> Bool {
        let normalizedValue = normalize(value)
        return normalizedValue == "com.microsoft.teams"
            || normalizedValue == "com.microsoft.teams2"
            || normalizedValue.hasPrefix("com.microsoft.teams")
    }

    private func telemostProcessAudioSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard isTelemost(app),
              telemostProcessAudioIsActive(audioActivity)
        else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.telemost_process_audio",
            confidence: "high",
            reason: "Yandex Telemost process is using audio.",
            startsImmediately: true
        )
    }

    private func telemostProcessAudioIsActive(_ audioActivity: AudioActivitySnapshot) -> Bool {
        audioActivity.processActivities.contains { activity in
            isTelemostBundleID(activity.bundleID) && activity.isRunningInput
        }
    }

    private func telemostMeetingWindowSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard isTelemost(app),
              audioActivity.microphoneActive,
              meetingWindowLooksActive(app) == true
        else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.telemost_meeting_window",
            confidence: "high",
            reason: "Yandex Telemost meeting window detected with microphone activity.",
            startsImmediately: true
        )
    }

    private func isTelemostBundleID(_ value: String) -> Bool {
        let normalizedValue = normalize(value)
        return normalizedValue == "ru.yandex.desktop.telemost"
            || normalizedValue.contains("telemost")
    }

    private func isGenericKnownCallApp(_ app: ActiveApplicationSnapshot) -> Bool {
        isTelegram(app) || isDiscord(app)
    }

    private func isTelegram(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return appTokens.contains("telegram")
            || appTokens.contains("ru.keepcoder.telegram")
            || appTokens.contains("org.telegram.desktop")
    }

    private func isDiscord(_ app: ActiveApplicationSnapshot) -> Bool {
        let appTokens = Set(tokens(for: app).map(normalize))
        return appTokens.contains("discord")
            || appTokens.contains("com.hnc.discord")
    }

    private func genericKnownCallAppProcessAudioSignal(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> AutoStartSignal? {
        guard genericKnownCallAppProcessAudioIsActive(for: app, audioActivity: audioActivity) else {
            return nil
        }

        return AutoStartSignal(
            ruleID: "autostart.v2.known_call_app",
            confidence: "high",
            reason: "\(sourceAppName(for: app)) process is using input and output audio."
        )
    }

    private func genericKnownCallAppProcessAudioIsActive(
        for app: ActiveApplicationSnapshot,
        audioActivity: AudioActivitySnapshot
    ) -> Bool {
        guard audioActivity.processActivityAvailable else {
            return false
        }

        return audioActivity.processActivities.contains { activity in
            genericKnownCallAppBundleID(activity.bundleID, matches: app)
                && activity.isRunningInput
                && activity.isRunningOutput
        }
    }

    private func genericKnownCallAppBundleID(_ bundleID: String, matches app: ActiveApplicationSnapshot) -> Bool {
        if isTelegram(app) {
            return isTelegramBundleID(bundleID)
        }

        if isDiscord(app) {
            return isDiscordBundleID(bundleID)
        }

        return false
    }

    private func isTelegramBundleID(_ value: String) -> Bool {
        let normalizedValue = normalize(value)
        return normalizedValue == "ru.keepcoder.telegram"
            || normalizedValue == "org.telegram.desktop"
            || normalizedValue.contains("telegram")
    }

    private func isDiscordBundleID(_ value: String) -> Bool {
        let normalizedValue = normalize(value)
        return normalizedValue == "com.hnc.discord"
            || normalizedValue.contains("discord")
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

public protocol RunningApplicationDetecting {
    func runningApplications() -> [ActiveApplicationSnapshot]
}

public protocol AudioActivityDetecting {
    func audioActivity() -> AudioActivitySnapshot
}

enum WindowTitleSelectionPolicy {
    static func preferredTitle(from titles: [String]) -> String? {
        let trimmedTitles = titles
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !trimmedTitles.isEmpty else {
            return nil
        }

        return trimmedTitles.joined(separator: " | ")
    }
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

        let titles = windows.compactMap { window -> String? in
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  pid_t(ownerPID) == processID,
                  let title = window[kCGWindowName as String] as? String
            else {
                return nil
            }

            return title
        }

        return WindowTitleSelectionPolicy.preferredTitle(from: titles)
        #else
        return nil
        #endif
    }
}

public final class WorkspaceRunningApplicationDetector: RunningApplicationDetecting {
    public init() {}

    public func runningApplications() -> [ActiveApplicationSnapshot] {
        let windowTitlesByProcessID = Self.windowTitlesByProcessID()

        return NSWorkspace.shared.runningApplications.compactMap { application -> ActiveApplicationSnapshot? in
            guard !application.isTerminated else {
                return nil
            }

            let name = application.localizedName ?? application.bundleIdentifier ?? ""
            let bundleID = application.bundleIdentifier ?? ""
            guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            else {
                return nil
            }

            return ActiveApplicationSnapshot(
                name: name,
                bundleID: bundleID,
                windowTitle: WindowTitleSelectionPolicy.preferredTitle(
                    from: windowTitlesByProcessID[application.processIdentifier] ?? []
                )
            )
        }
    }

    private static func windowTitlesByProcessID() -> [pid_t: [String]] {
        #if canImport(CoreGraphics)
        guard let windows = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements],
            kCGNullWindowID
        ) as? [[String: Any]] else {
            return [:]
        }

        var titlesByProcessID: [pid_t: [String]] = [:]
        for window in windows {
            guard let ownerPID = window[kCGWindowOwnerPID as String] as? Int,
                  let title = window[kCGWindowName as String] as? String
            else {
                continue
            }

            let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedTitle.isEmpty else {
                continue
            }

            titlesByProcessID[pid_t(ownerPID), default: []].append(trimmedTitle)
        }

        return titlesByProcessID
        #else
        return [:]
        #endif
    }
}
#endif

#if canImport(CoreAudio)
public final class CoreAudioActivityDetector: AudioActivityDetecting {
    public init() {}

    public func audioActivity() -> AudioActivitySnapshot {
        let processActivityResult = processAudioActivities()
        return AudioActivitySnapshot(
            microphoneActive: isDefaultDeviceRunning(selector: kAudioHardwarePropertyDefaultInputDevice),
            systemAudioActive: isDefaultDeviceRunning(selector: kAudioHardwarePropertyDefaultOutputDevice),
            processActivities: processActivityResult.activities,
            processActivityAvailable: processActivityResult.available
        )
    }

    private func processAudioActivities() -> (available: Bool, activities: [AudioProcessActivitySnapshot]) {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size = UInt32(0)
        let sizeStatus = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size
        )
        guard sizeStatus == noErr else {
            AppLogger.file(.warning, category: "autostart", "process audio activity unavailable size_status=\(sizeStatus)")
            return (false, [])
        }

        let count = Int(size) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else {
            return (true, [])
        }

        var processObjectIDs = [AudioObjectID](repeating: 0, count: count)
        let dataStatus = processObjectIDs.withUnsafeMutableBufferPointer { buffer in
            AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                buffer.baseAddress!
            )
        }
        guard dataStatus == noErr else {
            AppLogger.file(.warning, category: "autostart", "process audio activity unavailable data_status=\(dataStatus)")
            return (false, [])
        }

        let activities = processObjectIDs.compactMap { processObjectID -> AudioProcessActivitySnapshot? in
            guard processObjectID != kAudioObjectUnknown,
                  let processID = processID(for: processObjectID)
            else {
                return nil
            }

            let bundleID = bundleID(for: processID)
            guard !bundleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return nil
            }

            return AudioProcessActivitySnapshot(
                processID: Int32(processID),
                bundleID: bundleID,
                isRunningInput: boolProperty(kAudioProcessPropertyIsRunningInput, objectID: processObjectID),
                isRunningOutput: boolProperty(kAudioProcessPropertyIsRunningOutput, objectID: processObjectID)
            )
        }

        return (true, activities)
    }

    private func processID(for objectID: AudioObjectID) -> pid_t? {
        var processID = pid_t(0)
        var size = UInt32(MemoryLayout<pid_t>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioProcessPropertyPID,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &processID
        ) == noErr, processID > 0 else {
            return nil
        }

        return processID
    }

    private func bundleID(for processID: pid_t) -> String {
        #if canImport(AppKit)
        return NSRunningApplication(processIdentifier: processID)?.bundleIdentifier ?? ""
        #else
        return ""
        #endif
    }

    private func boolProperty(_ selector: AudioObjectPropertySelector, objectID: AudioObjectID) -> Bool {
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        guard AudioObjectGetPropertyData(
            objectID,
            &address,
            0,
            nil,
            &size,
            &value
        ) == noErr else {
            return false
        }

        return value != 0
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
            whitelist: AutoStartSettings.whitelistMigratingKnownDefaultAdditions(settings.whitelist),
            blacklist: settings.blacklist,
            cooldownSeconds: settings.cooldownSeconds,
            minDetectionDurationSeconds: settings.minDetectionDurationSeconds,
            shortRecordingThresholdSeconds: settings.shortRecordingThresholdSeconds,
            autoStopDelaySeconds: settings.autoStopDelaySeconds
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
        "com.openai.atlas": ["ChatGPT Atlas"],
        "com.openai.atlas.web": ["ChatGPT Atlas"],
        "com.microsoft.teams": ["Microsoft Teams", "Teams"],
        "com.microsoft.teams2": ["Microsoft Teams", "Teams"],
        "ru.yandex.desktop.telemost": ["Yandex Telemost", "Telemost", "Яндекс Телемост", "Телемост"],
        "ru.keepcoder.telegram": ["Telegram"],
        "org.telegram.desktop": ["Telegram"],
        "com.hnc.discord": ["Discord"]
    ]

    static let knownCallAppTokens: [String] = [
        "Zoom",
        "zoom.us",
        "us.zoom.xos",
        "Microsoft Teams",
        "Teams",
        "com.microsoft.teams",
        "com.microsoft.teams2",
        "Yandex Telemost",
        "Telemost",
        "Яндекс Телемост",
        "Телемост",
        "ru.yandex.desktop.telemost",
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
        "com.microsoft.edgemac",
        "ChatGPT Atlas",
        "com.openai.atlas",
        "com.openai.atlas.web"
    ]

    static let browserCallTitleTokens: [String] = [
        "Meet",
        "Zoom",
        "Zoom Meeting",
        "app.zoom.us",
        "zoom.us",
        "Teams",
        "KTalk",
        "МТС Линк",
        "SberJazz",
        "Встреча",
        "Собеседование",
        "Interview",
        "Call"
    ]

    static let browserZoomWebTitleTokens: [String] = [
        "Zoom Meeting",
        "app.zoom.us",
        "zoom.us"
    ]
}
