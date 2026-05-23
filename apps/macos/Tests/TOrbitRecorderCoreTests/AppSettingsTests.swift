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
        #expect(settings.autoStart.cooldownSeconds == 180)
        #expect(settings.autoStart.minDetectionDurationSeconds == 20)
        #expect(settings.autoStart.shortRecordingThresholdSeconds == 60)
        #expect(settings.storage.rootFolderPath == RecordingPaths.defaultRoot.path(percentEncoded: false))
        #expect(settings.privacy.localOnlyMode)
        #expect(settings.privacy.showRecordingIndicator)
        #expect(settings.privacy.showFocusModeReminder)
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
            isEnabled: false,
            whitelist: ["Zoom"],
            blacklist: ["Discord"],
            cooldownSeconds: 240,
            minDetectionDurationSeconds: 30,
            shortRecordingThresholdSeconds: 90
        )
        settings.storage.rootFolderPath = "/tmp/TOrbitRecorderCustom"
        settings.privacy.showRecordingIndicator = false

        AppSettingsStore.save(settings, defaults: defaults)
        let loaded = AppSettingsStore.load(defaults: defaults)

        #expect(loaded.recording.systemAudioEnabled == false)
        #expect(loaded.recording.mixedPreviewEnabled == false)
        #expect(loaded.autoStart.isEnabled == false)
        #expect(loaded.autoStart.whitelist == ["Zoom"])
        #expect(loaded.autoStart.blacklist == ["Discord"])
        #expect(loaded.autoStart.cooldownSeconds == 240)
        #expect(loaded.autoStart.minDetectionDurationSeconds == 30)
        #expect(loaded.autoStart.shortRecordingThresholdSeconds == 90)
        #expect(loaded.storage.rootFolderPath == "/tmp/TOrbitRecorderCustom")
        #expect(loaded.privacy.showRecordingIndicator == false)
    }

    private static func makeDefaults() throws -> UserDefaults {
        let suiteName = "com.torbit.recorder.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }
}
