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
        #expect(second.recordingSource?.ruleID == "autostart.v2.zoom")
        #expect(second.recordingSource?.confidence == "high")
        #expect(second.recordingSource?.reason == "Zoom active with microphone activity.")
    }

    @Test
    func zoomStartsFromSystemAudioWhenMicrophoneActivityDetectorIsFalse() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let activeApp = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom")
        #expect(decision.recordingSource?.confidence == "high")
        #expect(decision.recordingSource?.reason == "Zoom active with system audio activity.")
    }

    @Test
    func browserCallTitleStartsAfterMinimumDetectionDuration() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "QA mentorship - Google Meet"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )
        #expect(first.action == .wait)

        let second = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(second.action == .start)
        #expect(second.recordingSource?.ruleID == "autostart.v2.browser_title")
        #expect(second.recordingSource?.confidence == "high")
        #expect(second.recordingSource?.reason == "Browser call detected from active window title.")
    }

    @Test
    func browserWithoutTitleFallsBackToMediumConfidenceHeuristic() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(name: "Google Chrome", bundleID: "com.google.Chrome")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.browser_fallback")
        #expect(decision.recordingSource?.confidence == "medium")
        #expect(decision.recordingSource?.reason == "Browser call inferred from microphone and system audio activity.")
    }

    @Test
    func browserSystemAudioOnlyDoesNotStart() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - Music"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .microphoneInactive)
        #expect(decision.confidence == "low")
    }

    @Test
    func browserYouTubeTitleWithNoMicDoesNotStart() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - SwiftUI tutorial"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .microphoneInactive)
        #expect(decision.message.contains("YouTube"))
    }

    @Test
    func browserYouTubeTitleWithMicAndSystemDoesNotStartWhenTitleIsAvailable() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "YouTube - Live stream"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .browserTitleNotCall)
    }

    @Test
    func browserTitleDoesNotStartFromCallSubstringInsideAnotherWord() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "Callback hell explained - YouTube"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .browserTitleNotCall)
    }

    @Test
    func browserTitleTokensStartWhenMatchedAsCallWords() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Google Chrome"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "МТС Линк - Собеседование"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.browser_title")
    }

    @Test
    func askFirstModeReturnsAskInsteadOfStart() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            mode: .askFirst,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(name: "Zoom", bundleID: "us.zoom.xos")
        let now = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: now
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: now.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .ask)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom")
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
        #expect(AutoStartSettings(shortRecordingThresholdSeconds: 3).shortRecordingThresholdSeconds == 15)
        #expect(AutoStartSettings(shortRecordingThresholdSeconds: 900).shortRecordingThresholdSeconds == 300)
    }
}
