using Recny.Windows.Core.Recording;
using Recny.Windows.Core.Storage;
using Recny.Windows.Core.AutoStart;
using Recny.Windows.Core.Updates;

namespace Recny.Windows.Tests;

internal static class Program
{
    private static int Main()
    {
        var tests = new (string Name, Action Run)[]
        {
            ("recording paths create expected layout", RecordingPathsCreateExpectedLayout),
            ("metadata writer persists json", MetadataWriterPersistsJson),
            ("recording scanner sorts newest first", RecordingScannerSortsNewestFirst),
            ("auto-start starts only after stable activity", AutoStartStartsOnlyAfterStableActivity),
            ("auto-start start decision carries source process id", AutoStartStartDecisionCarriesSourceProcessId),
            ("auto-start resets when activity is interrupted", AutoStartResetsWhenActivityIsInterrupted),
            ("auto-start keeps recording while source audio continues", AutoStartKeepsRecordingWhileSourceAudioContinues),
            ("auto-start stops auto recordings after inactive grace", AutoStartStopsAutoRecordingsAfterInactiveGrace),
            ("update manifest decodes windows release", UpdateManifestDecodesWindowsRelease),
            ("version comparison handles beta and stable releases", VersionComparisonHandlesBetaAndStableReleases),
            ("update reminder runs daily and respects recording", UpdateReminderRunsDailyAndRespectsRecording),
            ("update reminder respects later and skipped versions", UpdateReminderRespectsLaterAndSkippedVersions),
            ("update notification presenter keeps recording state primary", UpdateNotificationPresenterKeepsRecordingStatePrimary),
            ("bug report url includes version and platform", BugReportUrlIncludesVersionAndPlatform)
        };

        foreach (var test in tests)
        {
            try
            {
                test.Run();
                Console.WriteLine($"PASS {test.Name}");
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine($"FAIL {test.Name}: {ex}");
                return 1;
            }
        }

        return 0;
    }

    private static void RecordingPathsCreateExpectedLayout()
    {
        var root = TempRoot();
        var startedAt = new DateTimeOffset(2026, 5, 31, 16, 30, 0, TimeSpan.Zero);
        var session = RecordingPaths.CreateSession(root, startedAt);

        Assert(session.SessionDirectory.StartsWith(Path.Combine(root, "Library", "2026", "05")));
        Assert(session.MicWavPath.EndsWith(Path.Combine("source", "mic.wav")));
        Assert(session.SystemWavPath.EndsWith(Path.Combine("source", "system.wav")));
        Assert(session.MixedWavPath.EndsWith(Path.Combine("export", "mixed.wav")));
        Assert(session.MetadataPath.EndsWith("metadata.json"));
    }

    private static void MetadataWriterPersistsJson()
    {
        var root = TempRoot();
        var session = RecordingPaths.CreateSession(root, DateTimeOffset.UtcNow);
        Directory.CreateDirectory(session.SourceDirectory);
        Directory.CreateDirectory(session.ExportDirectory);
        File.WriteAllText(session.MicWavPath, "mic");
        File.WriteAllText(session.SystemWavPath, "system");
        File.WriteAllText(session.MixedWavPath, "mixed");

        var result = new AudioPostProcessResult
        {
            MixedWavCreated = true
        };
        var metadata = RecordingMetadataFactory.Create(
            session,
            session.StartedAt.AddMinutes(3),
            TimeSpan.FromMinutes(3),
            "completed",
            result,
            null);

        MetadataWriter.Write(session.MetadataPath, metadata);
        var read = MetadataWriter.Read(session.MetadataPath);

        Assert(read.Id == session.Id);
        Assert(read.Status == "completed");
        Assert(read.Files.MicWav == "source/mic.wav");
        Assert(read.Files.SystemWav == "source/system.wav");
        Assert(read.Files.MixedWav == "export/mixed.wav");
    }

    private static void RecordingScannerSortsNewestFirst()
    {
        var root = TempRoot();
        var older = WriteMetadata(root, new DateTimeOffset(2026, 5, 30, 10, 0, 0, TimeSpan.Zero));
        var newer = WriteMetadata(root, new DateTimeOffset(2026, 5, 31, 10, 0, 0, TimeSpan.Zero));

        var recordings = RecordingScanner.Scan(root);

        Assert(recordings.Count == 2);
        Assert(recordings[0].Id == newer.Id);
        Assert(recordings[1].Id == older.Id);
    }

    private static RecordingSession WriteMetadata(string root, DateTimeOffset startedAt)
    {
        var session = RecordingPaths.CreateSession(root, startedAt);
        Directory.CreateDirectory(session.SourceDirectory);
        Directory.CreateDirectory(session.ExportDirectory);
        File.WriteAllText(session.MicWavPath, "mic");
        File.WriteAllText(session.SystemWavPath, "system");
        File.WriteAllText(session.MixedWavPath, "mixed");
        var metadata = RecordingMetadataFactory.Create(
            session,
            startedAt.AddMinutes(1),
            TimeSpan.FromMinutes(1),
            "completed",
            new AudioPostProcessResult { MixedWavCreated = true },
            null);
        MetadataWriter.Write(session.MetadataPath, metadata);
        return session;
    }

    private static void AutoStartStartsOnlyAfterStableActivity()
    {
        var engine = new AutoStartDecisionEngine(new AutoStartPolicy(
            StartDetectionDuration: TimeSpan.FromSeconds(10),
            StopGraceDuration: TimeSpan.FromSeconds(10)));
        var t0 = new DateTimeOffset(2026, 5, 31, 18, 0, 0, TimeSpan.Zero);

        var first = engine.Evaluate(CallActivitySnapshot.Active(t0, "Zoom", "Zoom is using audio"), RecordingState.Idle, null);
        var beforeThreshold = engine.Evaluate(CallActivitySnapshot.Active(t0.AddSeconds(9), "Zoom", "Zoom is using audio"), RecordingState.Idle, null);
        var atThreshold = engine.Evaluate(CallActivitySnapshot.Active(t0.AddSeconds(10), "Zoom", "Zoom is using audio"), RecordingState.Idle, null);

        Assert(first.Action == AutoStartActionKind.None);
        Assert(beforeThreshold.Action == AutoStartActionKind.None);
        Assert(atThreshold.Action == AutoStartActionKind.StartRecording);
        Assert(atThreshold.SourceApp == "Zoom");
    }

    private static void AutoStartResetsWhenActivityIsInterrupted()
    {
        var engine = new AutoStartDecisionEngine(new AutoStartPolicy(
            StartDetectionDuration: TimeSpan.FromSeconds(10),
            StopGraceDuration: TimeSpan.FromSeconds(10)));
        var t0 = new DateTimeOffset(2026, 5, 31, 18, 0, 0, TimeSpan.Zero);

        engine.Evaluate(CallActivitySnapshot.Active(t0, "Zoom", "Zoom is using audio"), RecordingState.Idle, null);
        engine.Evaluate(CallActivitySnapshot.Inactive(t0.AddSeconds(5), "No call-like audio"), RecordingState.Idle, null);
        var afterReset = engine.Evaluate(CallActivitySnapshot.Active(t0.AddSeconds(12), "Zoom", "Zoom is using audio"), RecordingState.Idle, null);

        Assert(afterReset.Action == AutoStartActionKind.None);
    }

    private static void AutoStartStartDecisionCarriesSourceProcessId()
    {
        var engine = new AutoStartDecisionEngine(new AutoStartPolicy(
            StartDetectionDuration: TimeSpan.FromSeconds(10),
            StopGraceDuration: TimeSpan.FromSeconds(10)));
        var t0 = new DateTimeOffset(2026, 5, 31, 18, 0, 0, TimeSpan.Zero);

        engine.Evaluate(CallActivitySnapshot.Active(t0, "Google Chrome", "Google Chrome has a call-like window title: Meet", 4242), RecordingState.Idle, null);
        var atThreshold = engine.Evaluate(CallActivitySnapshot.Active(t0.AddSeconds(10), "Google Chrome", "Google Chrome has a call-like window title: Meet", 4242), RecordingState.Idle, null);

        Assert(atThreshold.Action == AutoStartActionKind.StartRecording);
        Assert(atThreshold.SourceApp == "Google Chrome");
        Assert(atThreshold.ProcessId == 4242);
    }

    private static void AutoStartStopsAutoRecordingsAfterInactiveGrace()
    {
        var engine = new AutoStartDecisionEngine(new AutoStartPolicy(
            StartDetectionDuration: TimeSpan.FromSeconds(10),
            StopGraceDuration: TimeSpan.FromSeconds(10)));
        var t0 = new DateTimeOffset(2026, 5, 31, 18, 0, 0, TimeSpan.Zero);

        var firstInactive = engine.Evaluate(CallActivitySnapshot.Inactive(t0, "No call-like audio"), RecordingState.Recording, "autostart");
        var beforeGrace = engine.Evaluate(CallActivitySnapshot.Inactive(t0.AddSeconds(9), "No call-like audio"), RecordingState.Recording, "autostart");
        var atGrace = engine.Evaluate(CallActivitySnapshot.Inactive(t0.AddSeconds(10), "No call-like audio"), RecordingState.Recording, "autostart");

        Assert(firstInactive.Action == AutoStartActionKind.None);
        Assert(beforeGrace.Action == AutoStartActionKind.None);
        Assert(atGrace.Action == AutoStartActionKind.StopRecording);

        var manualRecording = engine.Evaluate(CallActivitySnapshot.Inactive(t0.AddSeconds(25), "No call-like audio"), RecordingState.Recording, "manual");
        Assert(manualRecording.Action == AutoStartActionKind.None);
    }

    private static void AutoStartKeepsRecordingWhileSourceAudioContinues()
    {
        var engine = new AutoStartDecisionEngine(new AutoStartPolicy(
            StartDetectionDuration: TimeSpan.FromSeconds(10),
            StopGraceDuration: TimeSpan.FromSeconds(10)));
        var t0 = new DateTimeOffset(2026, 5, 31, 18, 0, 0, TimeSpan.Zero);

        var afterWindowSwitch = engine.Evaluate(
            CallActivitySnapshot.Active(t0.AddSeconds(30), "Google Chrome", "Google Chrome is still using system audio for the active recording.", 4242),
            RecordingState.Recording,
            "autostart");

        Assert(afterWindowSwitch.Action == AutoStartActionKind.None);
    }

    private static void UpdateManifestDecodesWindowsRelease()
    {
        const string json = """
        {
          "schema_version": 1,
          "generated_at": "2026-06-03T08:00:00Z",
          "macos": {
            "version": "0.1.7",
            "display_version": "v0.1.7",
            "build": "8",
            "release_url": "https://github.com/tolcheev/recny-releases/releases/tag/recny-test-builds-2026-06-03-v7",
            "download_url": "https://github.com/tolcheev/recny-releases/releases/download/recny-test-builds-2026-06-03-v7/Recny-v0.1.7-macOS.dmg",
            "sha256_url": "https://github.com/tolcheev/recny-releases/releases/download/recny-test-builds-2026-06-03-v7/Recny-v0.1.7-macOS.dmg.sha256",
            "notes": "Permission and update fixes."
          },
          "windows": {
            "version": "0.2.5-beta",
            "display_version": "v0.2.5-beta",
            "build": "5",
            "release_url": "https://github.com/tolcheev/recny-releases/releases/tag/recny-test-builds-2026-06-03-v7",
            "download_url": "https://github.com/tolcheev/recny-releases/releases/download/recny-test-builds-2026-06-03-v7/Recny-Windows-v0.2.5-beta.zip",
            "sha256_url": "https://github.com/tolcheev/recny-releases/releases/download/recny-test-builds-2026-06-03-v7/Recny-Windows-v0.2.5-beta.zip.sha256",
            "notes": "Windows update checks."
          }
        }
        """;

        var manifest = AppUpdateChecker.DecodeManifest(json);

        Assert(manifest.Windows.Version == "0.2.5-beta");
        Assert(manifest.Windows.DownloadUrl.EndsWith("Recny-Windows-v0.2.5-beta.zip"));
    }

    private static void VersionComparisonHandlesBetaAndStableReleases()
    {
        Assert(AppVersion.Parse("v0.2.2-beta") < AppVersion.Parse("0.2.3-beta"));
        Assert(AppVersion.Parse("0.2.3-beta") < AppVersion.Parse("0.2.3"));
        Assert(AppVersion.Parse("0.2.3") > AppVersion.Parse("0.2.3-beta"));
    }

    private static void UpdateReminderRunsDailyAndRespectsRecording()
    {
        var now = new DateTimeOffset(2026, 6, 3, 12, 0, 0, TimeSpan.Zero);
        var state = new AppUpdateReminderState();

        Assert(AppUpdateReminderPolicy.ShouldRunAutomaticCheck(now, state, isRecording: false));
        Assert(!AppUpdateReminderPolicy.ShouldRunAutomaticCheck(now, state, isRecording: true));

        state.LastAutomaticCheckAt = now.AddHours(-23);
        Assert(!AppUpdateReminderPolicy.ShouldRunAutomaticCheck(now, state, isRecording: false));

        state.LastAutomaticCheckAt = now.AddHours(-25);
        Assert(AppUpdateReminderPolicy.ShouldRunAutomaticCheck(now, state, isRecording: false));
    }

    private static void UpdateReminderRespectsLaterAndSkippedVersions()
    {
        var now = new DateTimeOffset(2026, 6, 3, 12, 0, 0, TimeSpan.Zero);
        var release = new AppUpdateRelease(
            "0.2.5-beta",
            "v0.2.5-beta",
            "5",
            "https://example.com/release",
            "https://example.com/Recny.zip",
            null,
            null);
        var result = new AppUpdateCheckResult("0.2.3-beta", release);
        var state = new AppUpdateReminderState();

        Assert(AppUpdateReminderPolicy.ShouldSurfaceUpdate(result, state, now, isRecording: false));
        Assert(!AppUpdateReminderPolicy.ShouldSurfaceUpdate(result, state, now, isRecording: true));

        AppUpdateReminderPolicy.RemindLater(state, release, now);
        Assert(!AppUpdateReminderPolicy.ShouldSurfaceUpdate(result, state, now.AddMinutes(1), isRecording: false));
        Assert(AppUpdateReminderPolicy.ShouldSurfaceUpdate(result, state, now.AddHours(25), isRecording: false));

        AppUpdateReminderPolicy.Skip(state, release);
        Assert(!AppUpdateReminderPolicy.ShouldSurfaceUpdate(result, state, now.AddHours(25), isRecording: false));
    }

    private static void UpdateNotificationPresenterKeepsRecordingStatePrimary()
    {
        var idleWithUpdate = AppUpdateNotificationPresenter.Present(
            isRecording: false,
            update: new AppUpdateRelease(
                "0.2.5-beta",
                "v0.2.5-beta",
                "5",
                "https://example.com/release",
                "https://example.com/Recny.zip",
                null,
                null));

        Assert(idleWithUpdate.HasUpdate);
        Assert(idleWithUpdate.TrayText == "Recny update available: v0.2.5-beta");
        Assert(idleWithUpdate.UpdateMenuTitle == "Update available: v0.2.5-beta");

        var recordingWithUpdate = AppUpdateNotificationPresenter.Present(
            isRecording: true,
            update: new AppUpdateRelease(
                "0.2.5-beta",
                "v0.2.5-beta",
                "5",
                "https://example.com/release",
                "https://example.com/Recny.zip",
                null,
                null));

        Assert(recordingWithUpdate.HasUpdate);
        Assert(recordingWithUpdate.TrayText == "Recny is recording");
        Assert(recordingWithUpdate.UpdateMenuTitle == "Update available: v0.2.5-beta");
    }

    private static void BugReportUrlIncludesVersionAndPlatform()
    {
        var url = AppSupportLinks.BugReportUrl("0.2.5-beta", "windows");

        Assert(url.Contains("recny-releases/issues/new"));
        Assert(url.Contains("version%3A%200.2.5-beta"));
        Assert(url.Contains("platform%3A%20windows"));
    }

    private static string TempRoot()
    {
        var path = Path.Combine(Path.GetTempPath(), "recny-windows-tests", Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(path);
        return path;
    }

    private static void Assert(bool condition)
    {
        if (!condition)
        {
            throw new InvalidOperationException("Assertion failed.");
        }
    }
}
