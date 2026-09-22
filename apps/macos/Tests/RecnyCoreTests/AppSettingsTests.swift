import Foundation
import Testing
@testable import RecnyCore

struct AppSettingsTests {
    @Test
    func defaultsMatchMVPSettings() {
        let settings = AppSettings()

        #expect(settings.recording.audioQualityPreset == .standard)
        #expect(settings.recording.systemAudioEnabled)
        #expect(settings.recording.mixedPreviewEnabled)
        #expect(settings.recording.audioLevelingEnabled)
        #expect(settings.recording.audioLevelingMode == .balanced)
        #expect(settings.recording.microphoneDeviceID == nil)
        #expect(settings.autoStart.isEnabled)
        #expect(settings.autoStart.mode == .auto)
        #expect(settings.autoStart.cooldownSeconds == 180)
        #expect(settings.autoStart.minDetectionDurationSeconds == 20)
        #expect(settings.autoStart.shortRecordingThresholdSeconds == 60)
        #expect(settings.storage.rootFolderPath == RecordingPaths.defaultRoot.path(percentEncoded: false))
        #expect(settings.privacy.localOnlyMode)
        #expect(settings.privacy.showRecordingIndicator)
        #expect(settings.privacy.showFocusModeReminder)
        #expect(settings.privacy.showDockIcon == false)
        #expect(settings.privacy.launchAtLogin)
        #expect(settings.hotkeys.startStopHotkey == "")
        #expect(settings.hotkeys.addMarkerHotkey == "")
    }

    @Test
    func persistsSettingsLocally() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppSettings()
        settings.recording.systemAudioEnabled = false
        settings.recording.mixedPreviewEnabled = false
        settings.recording.audioLevelingEnabled = false
        settings.recording.audioLevelingMode = .conservative
        settings.autoStart = AutoStartSettings(
            mode: .askFirst,
            whitelist: ["Zoom"],
            blacklist: ["Discord"],
            cooldownSeconds: 240,
            minDetectionDurationSeconds: 30,
            shortRecordingThresholdSeconds: 90
        )
        settings.storage.rootFolderPath = "/tmp/RecnyCustom"
        settings.privacy.showRecordingIndicator = false
        settings.privacy.showDockIcon = false
        settings.privacy.launchAtLogin = true

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.recording.systemAudioEnabled)
        #expect(loaded.recording.mixedPreviewEnabled)
        #expect(loaded.recording.audioLevelingEnabled == false)
        #expect(loaded.recording.audioLevelingMode == .conservative)
        #expect(loaded.autoStart.mode == .askFirst)
        #expect(loaded.autoStart.isEnabled)
        #expect(loaded.autoStart.whitelist == ["Zoom"])
        #expect(loaded.autoStart.blacklist == ["Discord"])
        #expect(loaded.autoStart.cooldownSeconds == 240)
        #expect(loaded.autoStart.minDetectionDurationSeconds == 30)
        #expect(loaded.autoStart.shortRecordingThresholdSeconds == 90)
        #expect(loaded.storage.rootFolderPath == "/tmp/RecnyCustom")
        #expect(loaded.privacy.showRecordingIndicator == false)
        #expect(loaded.privacy.showDockIcon == false)
        #expect(loaded.privacy.launchAtLogin)
    }

    @Test
    func recordingSettingsDecodeLegacyDisabledOutputPayloadAsMVPRequiredOutputs() throws {
        let json = """
        {
          "audioQualityPreset": "standard",
          "microphoneDeviceID": "BuiltInMic",
          "systemAudioEnabled": false,
          "mixedPreviewEnabled": false,
          "audioLevelingEnabled": true,
          "audioLevelingMode": "balanced"
        }
        """

        let settings = try JSONDecoder().decode(
            RecordingSettings.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(settings.systemAudioEnabled)
        #expect(settings.mixedPreviewEnabled)
    }

    @Test
    func runtimeSettingsKeepMVPRequiredOutputsEnabled() {
        let settings = RecordingRuntimeSettings(
            systemAudioEnabled: false,
            mixedPreviewEnabled: false
        )

        #expect(settings.systemAudioEnabled)
        #expect(settings.mixedPreviewEnabled)
    }

    @Test
    func privacySettingsDecodeOldPayloadWithMenuBarAndLoginDefaults() throws {
        let json = """
        {
          "localOnlyMode": true,
          "showRecordingIndicator": false,
          "showFocusModeReminder": true
        }
        """

        let settings = try JSONDecoder().decode(
            PrivacySettings.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(settings.localOnlyMode)
        #expect(settings.showRecordingIndicator == false)
        #expect(settings.showFocusModeReminder)
        #expect(settings.showDockIcon == false)
        #expect(settings.launchAtLogin)
    }

    @Test
    func loadsExistingSettingsWithMenuBarAndLoginMigration() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppSettings()
        settings.privacy.showDockIcon = true
        settings.privacy.launchAtLogin = false

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.privacy.showDockIcon == false)
        #expect(loaded.privacy.launchAtLogin)
    }

    @Test
    func autoStartSettingsDecodeLegacyEnabledPayload() throws {
        let json = """
        {
          "isEnabled": false,
          "whitelist": ["Zoom"],
          "blacklist": [],
          "cooldownSeconds": 180,
          "minDetectionDurationSeconds": 20,
          "shortRecordingThresholdSeconds": 60
        }
        """

        let settings = try JSONDecoder().decode(
            AutoStartSettings.self,
            from: try #require(json.data(using: .utf8))
        )

        #expect(settings.mode == .off)
        #expect(!settings.isEnabled)
    }

    @Test
    func appSettingsStoreMigratesLegacyDefaultWhitelistToCurrentSafeDefaultCallApps() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppSettings()
        settings.autoStart = AutoStartSettings(
            mode: .auto,
            whitelist: [
                "Zoom",
                "Google Chrome",
                "Safari",
                "Firefox",
                "Yandex Browser",
                "Microsoft Edge",
                "Telegram",
                "Discord"
            ],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.autoStart.whitelist.contains("Microsoft Teams"))
        #expect(loaded.autoStart.whitelist.contains("ChatGPT Atlas"))
        #expect(loaded.autoStart.whitelist.contains("Yandex Telemost"))
        #expect(loaded.autoStart.whitelist.contains("Zoom"))
        #expect(!loaded.autoStart.whitelist.contains("Telegram"))
        #expect(!loaded.autoStart.whitelist.contains("Discord"))
    }

    @Test
    func appSettingsStoreMigratesPreviouslyMigratedDefaultWhitelistToIncludeChatGPTAtlas() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: "com.torbit.recorder.app.settings.autostart-whitelist-v2")
        var settings = AppSettings()
        settings.autoStart = AutoStartSettings(
            mode: .auto,
            whitelist: [
                "Zoom",
                "Google Chrome",
                "Safari",
                "Firefox",
                "Yandex Browser",
                "Microsoft Edge",
                "Telegram",
                "Discord",
                "Microsoft Teams"
            ],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.autoStart.whitelist.contains("ChatGPT Atlas"))
        #expect(loaded.autoStart.whitelist.contains("Microsoft Teams"))
        #expect(loaded.autoStart.whitelist.contains("Yandex Telemost"))
        #expect(!loaded.autoStart.whitelist.contains("Telegram"))
        #expect(!loaded.autoStart.whitelist.contains("Discord"))
    }

    @Test
    func appSettingsStoreRemovesUnsafeDefaultCallAppsAfterV3MigrationAlreadyRan() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: "com.torbit.recorder.app.settings.autostart-whitelist-v2")
        defaults.set(true, forKey: "com.torbit.recorder.app.settings.autostart-whitelist-v3")
        var settings = AppSettings()
        settings.autoStart = AutoStartSettings(
            mode: .auto,
            whitelist: [
                "Zoom",
                "Google Chrome",
                "Safari",
                "Firefox",
                "Yandex Browser",
                "Microsoft Edge",
                "Telegram",
                "Discord",
                "Microsoft Teams",
                "ChatGPT Atlas",
                "Yandex Telemost"
            ],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.autoStart.whitelist.contains("Zoom"))
        #expect(loaded.autoStart.whitelist.contains("Microsoft Teams"))
        #expect(loaded.autoStart.whitelist.contains("ChatGPT Atlas"))
        #expect(loaded.autoStart.whitelist.contains("Yandex Telemost"))
        #expect(!loaded.autoStart.whitelist.contains("Telegram"))
        #expect(!loaded.autoStart.whitelist.contains("Discord"))
    }

    @Test
    func appSettingsStoreDoesNotExpandCustomWhitelistAfterChatGPTAtlasMigration() throws {
        let defaults = try Self.makeDefaults()
        defaults.set(true, forKey: "com.torbit.recorder.app.settings.autostart-whitelist-v2")
        var settings = AppSettings()
        settings.autoStart = AutoStartSettings(
            mode: .auto,
            whitelist: ["Zoom", "Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.autoStart.whitelist == ["Zoom", "Telegram"])
    }

    @Test
    func appSettingsStoreDoesNotExpandCustomAutoStartWhitelist() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppSettings()
        settings.autoStart = AutoStartSettings(
            mode: .auto,
            whitelist: ["Zoom", "Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.autoStart.whitelist == ["Zoom", "Telegram"])
    }

    @Test
    func autoStartSettingsStoreMigratesLegacyDefaultWhitelistToCurrentSafeDefaultCallApps() throws {
        let defaults = try Self.makeDefaults()
        let legacySettings = AutoStartSettings(
            mode: .auto,
            whitelist: [
                "Zoom",
                "Google Chrome",
                "Safari",
                "Firefox",
                "Yandex Browser",
                "Microsoft Edge",
                "Telegram",
                "Discord"
            ],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AutoStartSettingsStore.save(legacySettings, defaults: defaults)
        let loaded = AutoStartSettingsStore.load(defaults: defaults)

        #expect(loaded.whitelist.contains("Microsoft Teams"))
        #expect(loaded.whitelist.contains("ChatGPT Atlas"))
        #expect(loaded.whitelist.contains("Yandex Telemost"))
        #expect(loaded.whitelist.contains("Zoom"))
        #expect(!loaded.whitelist.contains("Telegram"))
        #expect(!loaded.whitelist.contains("Discord"))
    }

    @Test
    func autoStartSettingsStoreDoesNotExpandCustomWhitelist() throws {
        let defaults = try Self.makeDefaults()
        let customSettings = AutoStartSettings(
            mode: .auto,
            whitelist: ["Zoom", "Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20,
            shortRecordingThresholdSeconds: 60
        )

        AutoStartSettingsStore.save(customSettings, defaults: defaults)
        let loaded = AutoStartSettingsStore.load(defaults: defaults)

        #expect(loaded.whitelist == ["Zoom", "Telegram"])
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "com.torbit.recorder.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
