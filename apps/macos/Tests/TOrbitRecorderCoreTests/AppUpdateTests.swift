import Foundation
import Testing
@testable import TOrbitRecorderCore

struct AppUpdateTests {
    @Test
    func comparesSemanticVersionsWithOptionalVPrefixAndPrerelease() {
        #expect(AppVersion("v0.1.4") < AppVersion("0.1.5"))
        #expect(AppVersion("0.2.3-beta") < AppVersion("0.2.3"))
        #expect(!(AppVersion("0.2.3") < AppVersion("0.2.3-beta")))
        #expect(AppVersion("0.2.3-beta") < AppVersion("0.2.4-beta"))
    }

    @Test
    func decodesManifestAndSelectsPlatformRelease() throws {
        let json = """
        {
          "schema_version": 1,
          "generated_at": "2026-06-03T08:00:00Z",
          "macos": {
            "version": "0.1.5",
            "display_version": "v0.1.5",
            "build": "6",
            "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v5",
            "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v5/ToRec-v0.1.5-macOS.dmg",
            "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v5/ToRec-v0.1.5-macOS.dmg.sha256",
            "notes": "Permission and update fixes."
          },
          "windows": {
            "version": "0.2.3-beta",
            "display_version": "v0.2.3-beta",
            "build": "3",
            "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v5",
            "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v5/ToRec-Windows-v0.2.3-beta.zip",
            "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v5/ToRec-Windows-v0.2.3-beta.zip.sha256",
            "notes": "Windows update checks."
          }
        }
        """.data(using: .utf8)!

        let manifest = try AppUpdateChecker.decodeManifest(json)

        #expect(manifest.release(for: .macOS).version == "0.1.5")
        #expect(manifest.release(for: .windows).version == "0.2.3-beta")
        #expect(manifest.release(for: .macOS).downloadURL.lastPathComponent == "ToRec-v0.1.5-macOS.dmg")
    }

    @Test
    func reportsUpdateAvailabilityFromCurrentAndLatestVersions() {
        let release = AppUpdateRelease(
            version: "0.1.5",
            displayVersion: "v0.1.5",
            build: "6",
            releaseURL: URL(string: "https://example.com/release")!,
            downloadURL: URL(string: "https://example.com/ToRec.dmg")!,
            sha256URL: nil,
            notes: nil
        )

        #expect(AppUpdateCheckResult(currentVersion: "v0.1.4", latestRelease: release).isUpdateAvailable)
        #expect(!AppUpdateCheckResult(currentVersion: "v0.1.5", latestRelease: release).isUpdateAvailable)
    }

    @Test
    func automaticUpdateChecksRunAtMostDailyAndNeverDuringRecording() {
        let now = Date(timeIntervalSince1970: 1_800_000)
        var state = AppUpdateReminderState()

        #expect(AppUpdateReminderPolicy.shouldRunAutomaticCheck(now: now, state: state, isRecording: false))
        #expect(!AppUpdateReminderPolicy.shouldRunAutomaticCheck(now: now, state: state, isRecording: true))

        state.lastAutomaticCheckAt = now.addingTimeInterval(-23 * 60 * 60)
        #expect(!AppUpdateReminderPolicy.shouldRunAutomaticCheck(now: now, state: state, isRecording: false))

        state.lastAutomaticCheckAt = now.addingTimeInterval(-25 * 60 * 60)
        #expect(AppUpdateReminderPolicy.shouldRunAutomaticCheck(now: now, state: state, isRecording: false))
    }

    @Test
    func updateReminderRespectsLaterAndSkippedVersions() {
        let now = Date(timeIntervalSince1970: 1_800_000)
        let release = AppUpdateRelease(
            version: "0.1.6",
            displayVersion: "v0.1.6",
            build: "7",
            releaseURL: URL(string: "https://example.com/release")!,
            downloadURL: URL(string: "https://example.com/ToRec.dmg")!,
            sha256URL: nil,
            notes: nil
        )
        let result = AppUpdateCheckResult(currentVersion: "v0.1.5", latestRelease: release)
        var state = AppUpdateReminderState()

        #expect(AppUpdateReminderPolicy.shouldSurfaceUpdate(result: result, state: state, now: now, isRecording: false))
        #expect(!AppUpdateReminderPolicy.shouldSurfaceUpdate(result: result, state: state, now: now, isRecording: true))

        AppUpdateReminderPolicy.remindLater(state: &state, release: release, now: now)
        #expect(!AppUpdateReminderPolicy.shouldSurfaceUpdate(result: result, state: state, now: now.addingTimeInterval(60), isRecording: false))
        #expect(AppUpdateReminderPolicy.shouldSurfaceUpdate(result: result, state: state, now: now.addingTimeInterval(25 * 60 * 60), isRecording: false))

        AppUpdateReminderPolicy.skip(state: &state, release: release)
        #expect(!AppUpdateReminderPolicy.shouldSurfaceUpdate(result: result, state: state, now: now.addingTimeInterval(25 * 60 * 60), isRecording: false))
    }

    @Test
    func bugReportURLIncludesVersionAndPlatform() throws {
        let url = try #require(AppSupportLinks.bugReportURL(version: "v0.1.6", platform: .macOS))
        let absolute = url.absoluteString

        #expect(absolute.contains("torec-releases/issues/new"))
        #expect(absolute.contains("version:%20v0.1.6"))
        #expect(absolute.contains("platform:%20macos"))
    }
}
