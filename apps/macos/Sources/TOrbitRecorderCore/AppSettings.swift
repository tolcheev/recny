import Foundation

public enum AudioQualityPreset: String, CaseIterable, Codable, Sendable {
    case standard
}

public struct RecordingSettings: Codable, Equatable, Sendable {
    public var audioQualityPreset: AudioQualityPreset
    public var microphoneDeviceID: String?
    public var systemAudioEnabled: Bool
    public var mixedPreviewEnabled: Bool

    public init(
        audioQualityPreset: AudioQualityPreset = .standard,
        microphoneDeviceID: String? = nil,
        systemAudioEnabled: Bool = true,
        mixedPreviewEnabled: Bool = true
    ) {
        self.audioQualityPreset = audioQualityPreset
        self.microphoneDeviceID = microphoneDeviceID
        self.systemAudioEnabled = systemAudioEnabled
        self.mixedPreviewEnabled = mixedPreviewEnabled
    }
}

public struct RecordingRuntimeSettings: Equatable, Sendable {
    public var systemAudioEnabled: Bool
    public var mixedPreviewEnabled: Bool
    public var shortRecordingThresholdSeconds: TimeInterval
    public var preferredMicrophoneDeviceID: String?

    public init(
        systemAudioEnabled: Bool = true,
        mixedPreviewEnabled: Bool = true,
        shortRecordingThresholdSeconds: TimeInterval = TaggingStatus.shortRecordingThresholdSeconds,
        preferredMicrophoneDeviceID: String? = nil
    ) {
        self.systemAudioEnabled = systemAudioEnabled
        self.mixedPreviewEnabled = mixedPreviewEnabled
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

    public init(
        localOnlyMode: Bool = true,
        showRecordingIndicator: Bool = true,
        showFocusModeReminder: Bool = true,
        showDockIcon: Bool = true
    ) {
        self.localOnlyMode = localOnlyMode
        self.showRecordingIndicator = showRecordingIndicator
        self.showFocusModeReminder = showFocusModeReminder
        self.showDockIcon = showDockIcon
    }

    enum CodingKeys: String, CodingKey {
        case localOnlyMode
        case showRecordingIndicator
        case showFocusModeReminder
        case showDockIcon
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.localOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .localOnlyMode) ?? true
        self.showRecordingIndicator = try container.decodeIfPresent(Bool.self, forKey: .showRecordingIndicator) ?? true
        self.showFocusModeReminder = try container.decodeIfPresent(Bool.self, forKey: .showFocusModeReminder) ?? true
        self.showDockIcon = try container.decodeIfPresent(Bool.self, forKey: .showDockIcon) ?? true
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

    public static func load(defaults: UserDefaults = .standard) -> AppSettings {
        guard let data = defaults.data(forKey: key),
              let settings = try? JSONDecoder().decode(AppSettings.self, from: data)
        else {
            return AppSettings()
        }

        return AppSettings(
            recording: settings.recording,
            autoStart: settings.autoStart,
            storage: settings.storage,
            hotkeys: settings.hotkeys,
            privacy: settings.privacy
        )
    }

    public static func save(_ settings: AppSettings, defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }

        defaults.set(data, forKey: key)
    }
}
