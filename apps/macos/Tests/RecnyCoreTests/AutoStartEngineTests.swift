import Foundation
import Testing
@testable import RecnyCore

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
    func zoomDoesNotStartFromGlobalAudioWhenZoomProcessAudioIsIdle() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(
                    microphoneActive: true,
                    systemAudioActive: true,
                    processActivities: [
                        AudioProcessActivitySnapshot(
                            processID: 44,
                            bundleID: "us.zoom.xos",
                            isRunningInput: false,
                            isRunningOutput: false
                        ),
                        AudioProcessActivitySnapshot(
                            processID: 55,
                            bundleID: "com.apple.Music",
                            isRunningInput: false,
                            isRunningOutput: true
                        )
                    ]
                ),
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
    func zoomStartsFromProcessOutputEvenWhenGlobalDetectorsAreQuiet() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(
                    microphoneActive: false,
                    systemAudioActive: false,
                    processActivities: [
                        AudioProcessActivitySnapshot(
                            processID: 44,
                            bundleID: "us.zoom.xos",
                            isRunningInput: false,
                            isRunningOutput: true
                        )
                    ]
                ),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom_process_audio")
        #expect(decision.recordingSource?.reason == "Zoom process is using audio.")
    }

    @Test
    func zoomStartsFromZoomHelperProcessAudio() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(
                    microphoneActive: false,
                    systemAudioActive: false,
                    processActivities: [
                        AudioProcessActivitySnapshot(
                            processID: 45,
                            bundleID: "us.zoom.ZoomDaemon",
                            isRunningInput: true,
                            isRunningOutput: false
                        )
                    ]
                ),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom_process_audio")
    }

    @Test
    func defaultWhitelistIncludesMicrosoftTeams() {
        #expect(AutoStartSettings.defaultWhitelist.contains("Microsoft Teams"))
    }

    @Test
    func defaultWhitelistIncludesChatGPTAtlasForBrowserZoom() {
        #expect(AutoStartSettings.defaultWhitelist.contains("ChatGPT Atlas"))
    }

    @Test
    func defaultWhitelistIncludesYandexTelemost() {
        #expect(AutoStartSettings.defaultWhitelist.contains("Yandex Telemost"))
    }

    @Test
    func defaultWhitelistExcludesTelegramAndDiscord() {
        #expect(!AutoStartSettings.defaultWhitelist.contains("Telegram"))
        #expect(!AutoStartSettings.defaultWhitelist.contains("Discord"))
    }

    @Test
    func yandexTelemostDoesNotStartFromGlobalMicAndSystemAudioOnly() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Yandex Telemost"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let telemost = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telemost,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )
        #expect(first.action == .ignore)
        #expect(first.reason == .processAudioInactive)

        let second = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telemost,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(second.action == .ignore)
        #expect(second.reason == .processAudioInactive)
        #expect(second.recordingSource == nil)
    }

    @Test
    func runningYandexTelemostCallWinsOverActiveTelegramWindow() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Yandex Telemost", "Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let telemost = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost"
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                runningApplications: [telemost],
                audioActivity: AudioActivitySnapshot(
                    microphoneActive: true,
                    systemAudioActive: true,
                    processActivities: [
                        AudioProcessActivitySnapshot(
                            processID: 700,
                            bundleID: "ru.yandex.desktop.telemost",
                            isRunningInput: true,
                            isRunningOutput: true
                        )
                    ]
                ),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Yandex Telemost")
        #expect(decision.recordingSource?.bundleID == "ru.yandex.desktop.telemost")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.telemost_process_audio")
    }

    @Test
    func telemostDoesNotStartAfterEndedCallFromHomeWindowAndOutputOnlyAudio() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Yandex Telemost"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let telemostHome = ActiveApplicationSnapshot(
            name: "Yandex Telemost",
            bundleID: "ru.yandex.desktop.telemost",
            windowTitle: "Yandex Telemost"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telemostHome,
                audioActivity: AudioActivitySnapshot(
                    microphoneActive: true,
                    systemAudioActive: true,
                    processActivities: [
                        AudioProcessActivitySnapshot(
                            processID: 700,
                            bundleID: "ru.yandex.desktop.telemost",
                            isRunningInput: false,
                            isRunningOutput: true
                        )
                    ]
                ),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .processAudioInactive)
        #expect(decision.recordingSource == nil)
    }

    @Test
    func teamsMeetingWindowStartsBeforeSystemAudioSpeaks() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Microsoft Teams"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let teams = ActiveApplicationSnapshot(
            name: "Microsoft Teams",
            bundleID: "com.microsoft.teams2",
            windowTitle: "Meeting with Vladislav Tolcheev"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: teams,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Microsoft Teams")
        #expect(decision.recordingSource?.bundleID == "com.microsoft.teams2")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.teams_meeting_window")
        #expect(decision.recordingSource?.confidence == "high")
        #expect(decision.recordingSource?.reason == "Microsoft Teams meeting window detected with microphone activity.")
    }

    @Test
    func runningTeamsMeetingStartsAfterUserSwitchesWindowsBeforeSystemAudioSpeaks() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Microsoft Teams"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let teams = ActiveApplicationSnapshot(
            name: "Microsoft Teams",
            bundleID: "com.microsoft.teams2",
            windowTitle: "Meeting with Vladislav Tolcheev"
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                runningApplications: [teams],
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Microsoft Teams")
        #expect(decision.recordingSource?.bundleID == "com.microsoft.teams2")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.teams_meeting_window")
    }

    @Test
    func runningTeamsMeetingRespectsCooldownWhenMeetingWindowIsActive() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Microsoft Teams"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let teams = ActiveApplicationSnapshot(
            name: "Microsoft Teams",
            bundleID: "com.microsoft.teams2",
            windowTitle: "Meeting with Vladislav Tolcheev"
        )
        let chrome = ActiveApplicationSnapshot(name: "Google Chrome", bundleID: "com.google.Chrome")
        let stoppedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: chrome,
                runningApplications: [teams],
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: stoppedAt,
                now: stoppedAt.addingTimeInterval(45)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .cooldownActive)
        #expect(decision.recordingSource == nil)
    }

    @Test
    func recentZoomContinuesAutoStartAfterSwitchingToAnotherWindow() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let observedZoom = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )
        #expect(observedZoom.action == .ignore)
        #expect(observedZoom.reason == .microphoneInactive)

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(45)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Zoom")
        #expect(decision.recordingSource?.bundleID == "us.zoom.xos")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom")
        #expect(decision.recordingSource?.reason == "Zoom recently active with system audio activity.")
    }

    @Test
    func recentZoomContinuationDoesNotBypassActiveRecording() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: nil,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: true,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(45)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .alreadyRecording)
    }

    @Test
    func recentZoomContinuationDoesNotBypassCooldown() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: zoom,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: nil,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: startedAt,
                now: startedAt.addingTimeInterval(45)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .cooldownActive)
    }

    @Test
    func runningZoomStartsAfterUserSwitchesToAnotherWindowWithSystemAudio() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                runningApplications: [zoom],
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Zoom")
        #expect(decision.recordingSource?.bundleID == "us.zoom.xos")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom")
        #expect(decision.recordingSource?.reason == "Zoom call detected with microphone and system audio activity.")
    }

    @Test
    func runningZoomMeetingStartsAfterUserSwitchesWindowsEvenBeforeSystemAudioSpeaks() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(
            name: "zoom.us",
            bundleID: "us.zoom.xos",
            windowTitle: "Zoom Meeting"
        )
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                runningApplications: [zoom],
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "Zoom")
        #expect(decision.recordingSource?.bundleID == "us.zoom.xos")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.zoom")
        #expect(decision.recordingSource?.reason == "Zoom meeting window detected with microphone activity.")
    }

    @Test
    func runningZoomRespectsCooldownWhenCallSignalIsStrong() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")
        let stoppedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                runningApplications: [zoom],
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: stoppedAt,
                now: stoppedAt.addingTimeInterval(45)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .cooldownActive)
        #expect(decision.recordingSource == nil)
    }

    @Test
    func runningZoomDoesNotStartFromSystemAudioOnlyInBackground() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let zoom = ActiveApplicationSnapshot(name: "zoom.us", bundleID: "us.zoom.xos")
        let codex = ActiveApplicationSnapshot(name: "Codex", bundleID: "com.openai.codex")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: codex,
                runningApplications: [zoom],
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .appNotWhitelisted)
    }

    @Test
    func telegramSystemAudioOnlyDoesNotStartWithoutMicrophoneActivity() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 20
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .microphoneInactive)
    }

    @Test
    func telegramMicrophoneOnlyDoesNotStartWithoutSystemAudio() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: AudioActivitySnapshot(microphoneActive: true, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(20)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .systemAudioInactive)
        #expect(decision.recordingSource == nil)
    }

    @Test
    func telegramStartsOnlyWhenTelegramProcessInputAndOutputAreActive() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let audio = AudioActivitySnapshot(
            microphoneActive: false,
            systemAudioActive: false,
            processActivities: [
                AudioProcessActivitySnapshot(
                    processID: 100,
                    bundleID: "ru.keepcoder.Telegram",
                    isRunningInput: true,
                    isRunningOutput: true
                )
            ]
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(20)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.known_call_app")
        #expect(decision.recordingSource?.reason == "Telegram process is using input and output audio.")
    }

    @Test
    func telegramPlaybackWithGlobalMicrophoneActivityDoesNotStartWithoutTelegramInput() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Telegram"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let telegram = ActiveApplicationSnapshot(name: "Telegram", bundleID: "ru.keepcoder.Telegram")
        let audio = AudioActivitySnapshot(
            microphoneActive: true,
            systemAudioActive: true,
            processActivities: [
                AudioProcessActivitySnapshot(
                    processID: 100,
                    bundleID: "ru.keepcoder.Telegram",
                    isRunningInput: false,
                    isRunningOutput: true
                ),
                AudioProcessActivitySnapshot(
                    processID: 200,
                    bundleID: "com.apple.QuickTimePlayerX",
                    isRunningInput: true,
                    isRunningOutput: false
                )
            ]
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let second = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: telegram,
                audioActivity: audio,
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(20)
            ),
            settings: settings
        )

        #expect(first.action == .ignore)
        #expect(first.reason == .processAudioInactive)
        #expect(second.action == .ignore)
        #expect(second.reason == .processAudioInactive)
        #expect(second.recordingSource == nil)
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
    func chatGPTAtlasZoomWebMeetingStartsAfterMinimumDetectionDuration() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "ChatGPT Atlas",
            bundleID: "com.openai.atlas.web",
            windowTitle: "Zoom Meeting Anton Nazarov"
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
        #expect(first.reason == .waitingForMinDetectionDuration)

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
        #expect(second.reason == .startRecording)
        #expect(second.recordingSource?.appName == "ChatGPT Atlas")
        #expect(second.recordingSource?.bundleID == "com.openai.atlas.web")
        #expect(second.recordingSource?.ruleID == "autostart.v2.browser_title")
        #expect(second.recordingSource?.confidence == "high")
        #expect(second.recordingSource?.reason == "Browser call detected from active window title.")
    }

    @Test
    func chatGPTAtlasZoomWebDomainStartsAfterMinimumDetectionDuration() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "ChatGPT Atlas",
            bundleID: "com.openai.atlas.web",
            windowTitle: "app.zoom.us"
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
    func chatGPTAtlasZoomWebDomainStartsWhenMicrophoneIsMutedButSystemAudioIsActive() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "ChatGPT Atlas",
            bundleID: "com.openai.atlas",
            windowTitle: "app.zoom.us"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        #expect(first.action == .wait)
        #expect(first.reason == .waitingForMinDetectionDuration)

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "ChatGPT Atlas")
        #expect(decision.recordingSource?.bundleID == "com.openai.atlas")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.browser_zoom_web_title")
        #expect(decision.recordingSource?.confidence == "high")
        #expect(decision.recordingSource?.reason == "Zoom Web detected from active browser title and system audio activity.")
    }

    @Test
    func chatGPTAtlasZoomMeetingTitleStartsWhenMicrophoneIsMutedButSystemAudioIsActive() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "ChatGPT Atlas",
            bundleID: "com.openai.atlas",
            windowTitle: "Zoom Meeting Anton Nazarov"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        _ = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.recordingSource?.ruleID == "autostart.v2.browser_zoom_web_title")
    }

    @Test
    func runningChatGPTAtlasZoomWebStartsWhenRecnyIsForeground() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let recnyApp = ActiveApplicationSnapshot(name: "Recny", bundleID: "com.torbit.recorder")
        let atlas = ActiveApplicationSnapshot(
            name: "ChatGPT Atlas",
            bundleID: "com.openai.atlas",
            windowTitle: "Zoom Meeting Anton Nazarov"
        )
        let startedAt = Date(timeIntervalSince1970: 1_716_468_000)

        let first = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: recnyApp,
                runningApplications: [atlas],
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt
            ),
            settings: settings
        )

        #expect(first.action == .wait)
        #expect(first.reason == .waitingForMinDetectionDuration)

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: recnyApp,
                runningApplications: [atlas],
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: startedAt.addingTimeInterval(15)
            ),
            settings: settings
        )

        #expect(decision.action == .start)
        #expect(decision.reason == .startRecording)
        #expect(decision.recordingSource?.appName == "ChatGPT Atlas")
        #expect(decision.recordingSource?.ruleID == "autostart.v2.browser_zoom_web_title")
    }

    @Test
    func runningBrowserGenericCallTitleDoesNotStartWhenMicrophoneIsMutedAndRecnyIsForeground() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: AutoStartSettings.defaultWhitelist,
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let recnyApp = ActiveApplicationSnapshot(name: "Recny", bundleID: "com.torbit.recorder")
        let chrome = ActiveApplicationSnapshot(
            name: "Google Chrome",
            bundleID: "com.google.Chrome",
            windowTitle: "QA mentorship - Google Meet"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: recnyApp,
                runningApplications: [chrome],
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: true),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .appNotWhitelisted)
        #expect(decision.recordingSource == nil)
    }

    @Test
    func windowTitleSelectionSkipsBlankUtilityWindowsBeforeCallTitle() {
        let title = WindowTitleSelectionPolicy.preferredTitle(from: [
            "",
            "   ",
            "Zoom Meeting Anton Nazarov"
        ])

        #expect(title == "Zoom Meeting Anton Nazarov")
    }

    @Test
    func browserGenericCallTitleDoesNotStartWhenMicrophoneIsMuted() {
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
        #expect(decision.recordingSource == nil)
    }

    @Test
    func browserWithoutTitleDoesNotStartFromAudioActivityOnly() {
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

        #expect(decision.action == .ignore)
        #expect(decision.reason == .browserTitleNotCall)
        #expect(decision.recordingSource == nil)
        #expect(decision.message == "Browser window title is unavailable or does not look like a call.")
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
        #expect(!decision.message.contains("YouTube"))
        #expect(!decision.message.contains("SwiftUI"))
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
    func ignoreDecisionDoesNotLeakNonCallBrowserWindowTitle() {
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
            windowTitle: "Candidate Ivan Petrov - Compensation notes"
        )

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
        #expect(!decision.message.contains("Ivan"))
        #expect(!decision.message.contains("Compensation"))
    }

    @Test
    func microphoneInactiveDecisionDoesNotLeakWindowTitle() {
        var engine = AutoStartEngine()
        let settings = AutoStartSettings(
            isEnabled: true,
            whitelist: ["Zoom"],
            blacklist: [],
            cooldownSeconds: 180,
            minDetectionDurationSeconds: 15
        )
        let activeApp = ActiveApplicationSnapshot(
            name: "Zoom",
            bundleID: "us.zoom.xos",
            windowTitle: "ACME confidential interview"
        )

        let decision = engine.evaluate(
            AutoStartEvaluationContext(
                activeApplication: activeApp,
                audioActivity: AudioActivitySnapshot(microphoneActive: false, systemAudioActive: false),
                isAlreadyRecording: false,
                lastStoppedAt: nil,
                now: Date(timeIntervalSince1970: 1_716_468_000)
            ),
            settings: settings
        )

        #expect(decision.action == .ignore)
        #expect(decision.reason == .microphoneInactive)
        #expect(!decision.message.contains("ACME"))
        #expect(!decision.message.contains("confidential"))
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
        #expect(cooldown.recordingSource == nil)

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
