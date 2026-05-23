import Foundation
import Testing
@testable import TOrbitRecorderCore

struct AutoStartEngineTests {
    @Test
    func startsKnownCallAppAfterMinimumDetectionDuration() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(name: "Zoom", bundleID: "us.zoom.xos")
        let audio = AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false)
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )
        #expect(first.action == .wait)
        #expect(first.reason == .waitingForMinDetectionDuration)

        let second = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(second.action == .start)
        #expect(second.reason == .startRecording)
        #expect(second.recordingSource?.appName == "Zoom")
        #expect(second.recordingSource?.bundleID == "us.zoom.xos")
        #expect(second.recordingSource?.trigger == "autostart")
        #expect(second.recordingSource?.ruleID == "autostart.v1")
    }

    @Test
    func browserRequiresSystemAudioActivity() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(name: "Google Chrome", bundleID: "com.google.Chrome")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .systemAudioInactive)
    }

    @Test
    func blocksBlacklistRecordingAndCooldown() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: ["us.zoom.xos"],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(name: "Zoom", bundleID: "us.zoom.xos")
        let audio = AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true)
        let now = Date(timeIntervalSince1970: 1_716_468_000)

        let blacklisted = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: now
            ),
            settings: settings
        )
        #expect(blacklisted.action == .ignore)
        #expect(blacklisted.reason == .appBlacklisted)

        let cooldownSettings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let cooldown = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: now.addingTimeInterval(-60),
                now: now
            ),
            settings: cooldownSettings
        )
        #expect(cooldown.action == .ignore)
        #expect(cooldown.reason == .cooldownActive)

        let alreadyRecording = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: audio,
                isAlreadyRecording: true,
                lastStoppedAt: nil,
                now: now
            ),
            settings: cooldownSettings
        )
        #expect(alreadyRecording.action == .ignore)
        #expect(alreadyRecording.reason == .alreadyRecording)
    }

    @Test
    func clampsMinimumDetectionDurationToMvpRange() {
        #expect(AutoStartSettings(minDetectionDurationSeconds: 3).minDetectionDurationSeconds == 15)
        #expect(AutoStartSettings(minDetectionDurationSeconds: 90).minDetectionDurationSeconds == 30)
    }
}
