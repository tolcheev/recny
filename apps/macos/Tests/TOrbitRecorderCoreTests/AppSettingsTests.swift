import Foundation
import Testing
@testable import TOrbitRecorderCore

struct AppSettingsTests {
    @Test
    func defaultsMatchMVPSettings() {
        let settings = AppSettings()

        #expect(settings.recording.audioQualityPreset == .standard)
        #expect(settings.recording.systemAudioEnabled)
        #expect(settings.recording.mixedPreviewEnabled)
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
        #expect(settings.privacy.showDockIcon)
        #expect(settings.privacy.launchAtLogin == false)
        #expect(settings.hotkeys.startStopHotkey == "")
        #expect(settings.hotkeys.addMarkerHotkey == "")
    }

    @Test
    func persistsSettingsLocally() throws {
        let defaults = try Self.makeDefaults()
        var settings = AppSettings()
        settings.recording.systemAudioEnabled = false
        settings.recording.mixedPreviewEnabled = false
        settings.autoStart = AutoStartSettings(
            mode: .askFirst,
            whitelist: ["Zoom"],
            blacklist: ["Discord"],
            cooldownSeconds: 240,
            minDetectionDurationSeconds: 30,
            shortRecordingThresholdSeconds: 90
        )
        settings.storage.rootFolderPath = "/tmp/TOrbitRecorderCustom"
        settings.privacy.showRecordingIndicator = false
        settings.privacy.showDockIcon = false
        settings.privacy.launchAtLogin = true

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.recording.systemAudioEnabled == false)
        #expect(loaded.recording.mixedPreviewEnabled == false)
        #expect(loaded.autoStart.mode == .askFirst)
        #expect(loaded.autoStart.isEnabled)
        #expect(loaded.autoStart.whitelist == ["Zoom"])
        #expect(loaded.autoStart.blacklist == ["Discord"])
        #expect(loaded.autoStart.cooldownSeconds == 240)
        #expect(loaded.autoStart.minDetectionDurationSeconds == 30)
        #expect(loaded.autoStart.shortRecordingThresholdSeconds == 90)
        #expect(loaded.storage.rootFolderPath == "/tmp/TOrbitRecorderCustom")
        #expect(loaded.privacy.showRecordingIndicator == false)
        #expect(loaded.privacy.showDockIcon == false)
        #expect(loaded.privacy.launchAtLogin)
    }

    @Test
    func privacySettingsDecodeOldPayloadWithDockIconDefaultOn() throws {
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
        #expect(settings.showDockIcon)
        #expect(settings.launchAtLogin == false)
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

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "com.torbit.recorder.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
