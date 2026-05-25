import Foundation

public enum AudioQualityPreset: String, CaseIterable, Codable, Sendable {
    case compact
    case standard
    case high

    public var displayName: String {
        switch self {
        case .compact:
            return "Compact"
        case .standard:
            return "Standard"
        case .high:
            return "High"
        }
    }

    public var sampleRate: Double {
        48_000
    }

    public var microphoneBitrate: Int {
        switch self {
        case .compact:
            return 96_000
        case .standard:
            return 128_000
        case .high:
            return 192_000
        }
    }

    public var systemAudioBitrate: Int {
        switch self {
        case .compact:
            return 96_000
        case .standard:
            return 128_000
        case .high:
            return 192_000
        }
    }

    public var mixedPreviewBitrate: Int {
        switch self {
        case .compact:
            return 80_000
        case .standard:
            return 96_000
        case .high:
            return 128_000
        }
    }
}

public struct RecordingSettings: Codable, Equatable, Sendable {
    public var audioQualityPreset: AudioQualityPreset
    public var microphoneDeviceID: String?
    public var systemAudioEnabled: Bool
    public var mixedPreviewEnabled: Bool
    public var audioLevelingEnabled: Bool
    public var audioLevelingMode: AudioLevelingMode

    public init(
        audioQualityPreset: AudioQualityPreset = .standard,
        microphoneDeviceID: String? = nil,
        systemAudioEnabled: Bool = true,
        mixedPreviewEnabled: Bool = true,
        audioLevelingEnabled: Bool = true,
        audioLevelingMode: AudioLevelingMode = .balanced
    ) {
        self.audioQualityPreset = audioQualityPreset
        self.microphoneDeviceID = microphoneDeviceID
        self.systemAudioEnabled = systemAudioEnabled
        self.mixedPreviewEnabled = mixedPreviewEnabled
        self.audioLevelingEnabled = audioLevelingEnabled
        self.audioLevelingMode = audioLevelingMode
    }

    enum CodingKeys: String, CodingKey {
        case audioQualityPreset
        case microphoneDeviceID
        case systemAudioEnabled
        case mixedPreviewEnabled
        case audioLevelingEnabled
        case audioLevelingMode
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.audioQualityPreset = try container.decodeIfPresent(AudioQualityPreset.self, forKey: .audioQualityPreset) ?? .standard
        self.microphoneDeviceID = try container.decodeIfPresent(String.self, forKey: .microphoneDeviceID)
        self.systemAudioEnabled = try container.decodeIfPresent(Bool.self, forKey: .systemAudioEnabled) ?? true
        self.mixedPreviewEnabled = try container.decodeIfPresent(Bool.self, forKey: .mixedPreviewEnabled) ?? true
        self.audioLevelingEnabled = try container.decodeIfPresent(Bool.self, forKey: .audioLevelingEnabled) ?? true
        let decodedMode = try container.decodeIfPresent(AudioLevelingMode.self, forKey: .audioLevelingMode) ?? .balanced
        self.audioLevelingMode = decodedMode.isImplemented ? decodedMode : .balanced
    }
}

public struct RecordingRuntimeSettings: Equatable, Sendable {
    public var audioQualityPreset: AudioQualityPreset
    public var systemAudioEnabled: Bool
    public var mixedPreviewEnabled: Bool
    public var audioLevelingEnabled: Bool
    public var audioLevelingMode: AudioLevelingMode
    public var shortRecordingThresholdSeconds: TimeInterval
    public var preferredMicrophoneDeviceID: String?

    public init(
        audioQualityPreset: AudioQualityPreset = .standard,
        systemAudioEnabled: Bool = true,
        mixedPreviewEnabled: Bool = true,
        audioLevelingEnabled: Bool = true,
        audioLevelingMode: AudioLevelingMode = .balanced,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds,
        preferredMicrophoneDeviceID: String? = nil
    ) {
        self.audioQualityPreset = audioQualityPreset
        self.systemAudioEnabled = systemAudioEnabled
        self.mixedPreviewEnabled = mixedPreviewEnabled
        self.audioLevelingEnabled = audioLevelingEnabled
        self.audioLevelingMode = audioLevelingMode.isImplemented ? audioLevelingMode : .balanced
        self.shortRecordingThresholdSeconds = max(0, shortRecordingThresholdSeconds)
        self.preferredMicrophoneDeviceID = preferredMicrophoneDeviceID
    }
}

public struct StorageSettings: Codable, Equatable, Sendable {
    public var rootFolderPath: String

    public init(rootFolderPath: String = RecordingPaths.defaultRoot.path(percentEncoded: false)) {
        self.rootFolderPath = rootFolderPath
    }

    public var rootFolderURL: URL {
        URL(fileURLWithPath: rootFolderPath)
    }
}

public struct HotkeySettings: Codable, Equatable, Sendable {
    public var startStopHotkey: String
    public var addMarkerHotkey: String

    public init(startStopHotkey: String = "", addMarkerHotkey: String = "") {
        self.startStopHotkey = startStopHotkey
        self.addMarkerHotkey = addMarkerHotkey
    }
}

public struct PrivacySettings: Codable, Equatable, Sendable {
    public var localOnlyMode: Bool
    public var showRecordingIndicator: Bool
    public var showFocusModeReminder: Bool
    public var showDockIcon: Bool
    public var launchAtLogin: Bool

    public init(
        localOnlyMode: Bool = true,
        showRecordingIndicator: Bool = true,
        showFocusModeReminder: Bool = true,
        showDockIcon: Bool = false,
        launchAtLogin: Bool = true
    ) {
        self.localOnlyMode = localOnlyMode
        self.showRecordingIndicator = showRecordingIndicator
        self.showFocusModeReminder = showFocusModeReminder
        self.showDockIcon = showDockIcon
        self.launchAtLogin = launchAtLogin
    }

    enum CodingKeys: String, CodingKey {
        case localOnlyMode
        case showRecordingIndicator
        case showFocusModeReminder
        case showDockIcon
        case launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.localOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .localOnlyMode) ?? true
        self.showRecordingIndicator = try container.decodeIfPresent(Bool.self, forKey: .showRecordingIndicator) ?? true
        self.showFocusModeReminder = try container.decodeIfPresent(Bool.self, forKey: .showFocusModeReminder) ?? true
        self.showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? false
        self.launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
    }
}

public struct AppSettings: Codable, Equatable, Sendable {
    public var recording: RecordingSettings
    public var autoStart: AutoStartSettings
    public var storage: StorageSettings
    public var hotkeys: HotkeySettings
    public var privacy: PrivacySettings

    public init(
        recording: RecordingSettings = RecordingSettings(),
        autoStart: AutoStartSettings = AutoStartSettings(),
        storage: StorageSettings = StorageSettings(),
        hotkeys: HotkeySettings = HotkeySettings(),
        privacy: PrivacySettings = PrivacySettings()
    ) {
        self.recording = recording
        self.autoStart = autoStart
        self.storage = storage
        self.hotkeys = hotkeys
        self.privacy = privacy
    }
}

public enum AppSettingsStore {
    private static let key = "com.torbit.recorder.app.settings.v1"
    private static let behaviorDefaultsMigrationKey = "com.torbit.recorder.app.settings.behavior-defaults-v2"

    public static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            let settings = AppSettings()
            defaults.set(true, forKey: behaviorDefaultsMigrationKey)
            save(settings, defaults: defaults)
            return settings
        }

        var resolvedSettings = AppSettings(
            recording: settings.recording,
            autoStart: settings.autoStart,
            storage: settings.storage,
            hotkeys: settings.hotkeys,
            privacy: settings.privacy
        )

        if !defaults.bool(forKey: behaviorDefaultsMigrationKey) {
            resolvedSettings.privacy.showDockIcon = false
            resolvedSettings.privacy.launchAtLogin = true
            defaults.set(true, forKey: behaviorDefaultsMigrationKey)
            save(resolvedSettings, defaults: defaults)
        }

        return resolvedSettings
    }

    public static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
