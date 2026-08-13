using System.Diagnostics;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using Recny.Windows.Core.AutoStart;

namespace Recny.Windows;

public sealed class WindowsCallActivityDetector
{
    private static readonly HashSet<string> DesktopCallApps = new(StringComparer.OrdinalIgnoreCase)
    {
        "zoom",
        "zoommeeting",
        "teams",
        "ms-teams",
        "msteams",
        "telegram",
        "discord",
        "slack",
        "skype",
        "webex",
        "ciscocollabhost",
        "ktalk",
        "k-talk"
    };

    private static readonly HashSet<string> Browsers = new(StringComparer.OrdinalIgnoreCase)
    {
        "chrome",
        "msedge",
        "firefox",
        "brave",
        "opera",
        "browser",
        "yandex",
        "arc"
    };

    private static readonly string[] CallTitleHints =
    [
        "meet",
        "google meet",
        "zoom",
        "teams",
        "ktalk",
        "k-talk",
        "call",
        "huddle",
        "jitsi",
        "whereby",
        "discord",
        "interview",
        "собесед",
        "созвон",
        "звонок"
    ];

    public CallActivitySnapshot Capture()
    {
        var now = DateTimeOffset.Now;

        try
        {
            foreach (var candidate in CaptureAudioCandidates())
            {
                if (DesktopCallApps.Contains(candidate.ProcessName))
                {
                    return candidate.ToSnapshot(now, $"{candidate.SourceApp} is using system audio.");
                }

                if (Browsers.Contains(candidate.ProcessName) && LooksLikeCallWindow(candidate.WindowTitle))
                {
                    return candidate.ToSnapshot(
                        now,
                        $"{candidate.SourceApp} has a call-like window title: {candidate.WindowTitle}");
                }
            }
        }
        catch (Exception ex)
        {
            return CallActivitySnapshot.Inactive(now, $"Call activity detection failed: {ex.Message}");
        }

        return CallActivitySnapshot.Inactive(now, "No call-like audio session.");
    }

    public CallActivitySnapshot CaptureForActiveRecording(string? sourceApp, int? sourceProcessId)
    {
        var now = DateTimeOffset.Now;

        if (string.IsNullOrWhiteSpace(sourceApp))
        {
            return Capture();
        }

        try
        {
            var candidates = CaptureAudioCandidates();
            if (sourceProcessId is > 0)
            {
                var sameProcess = candidates.FirstOrDefault(candidate => candidate.ProcessId == sourceProcessId.Value);
                if (sameProcess is not null)
                {
                    return sameProcess.ToSnapshot(
                        now,
                        $"{sameProcess.SourceApp} is still using system audio for the active recording.");
                }
            }

            var sameSource = candidates.FirstOrDefault(candidate =>
                string.Equals(candidate.SourceApp, sourceApp, StringComparison.OrdinalIgnoreCase));
            if (sameSource is not null)
            {
                return sameSource.ToSnapshot(
                    now,
                    $"{sameSource.SourceApp} is still using system audio for the active recording.");
            }
        }
        catch (Exception ex)
        {
            return CallActivitySnapshot.Inactive(now, $"Active recording detection failed: {ex.Message}");
        }

        return CallActivitySnapshot.Inactive(now, $"No active audio session for {sourceApp}.");
    }

    private static List<AudioSessionCandidate> CaptureAudioCandidates()
    {
        using var enumerator = new MMDeviceEnumerator();
        using var renderDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
        var sessions = renderDevice.AudioSessionManager.Sessions;
        var candidates = new List<AudioSessionCandidate>();

        for (var index = 0; index < sessions.Count; index++)
        {
            using var session = sessions[index];
            if (session.State != AudioSessionState.AudioSessionStateActive || session.IsSystemSoundsSession)
            {
                continue;
            }

            var processId = unchecked((int)session.GetProcessID);
            if (processId <= 0 || processId == Environment.ProcessId)
            {
                continue;
            }

            var candidate = TryBuildCandidate(processId);
            if (candidate is not null)
            {
                candidates.Add(candidate);
            }
        }

        return candidates;
    }

    private static AudioSessionCandidate? TryBuildCandidate(int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            var processName = process.ProcessName;
            var title = process.MainWindowTitle ?? "";

            return new AudioSessionCandidate(
                processId,
                processName,
                NormalizeAppName(processName),
                title);
        }
        catch
        {
            return null;
        }
    }

    private static bool LooksLikeCallWindow(string title)
    {
        if (string.IsNullOrWhiteSpace(title))
        {
            return false;
        }

        return CallTitleHints.Any(hint => title.Contains(hint, StringComparison.OrdinalIgnoreCase));
    }

    private static string NormalizeAppName(string processName) =>
        processName.Equals("chrome", StringComparison.OrdinalIgnoreCase) ? "Google Chrome" :
        processName.Equals("msedge", StringComparison.OrdinalIgnoreCase) ? "Microsoft Edge" :
        processName.Equals("firefox", StringComparison.OrdinalIgnoreCase) ? "Firefox" :
        processName.Equals("zoom", StringComparison.OrdinalIgnoreCase) ? "Zoom" :
        processName.Equals("telegram", StringComparison.OrdinalIgnoreCase) ? "Telegram" :
        processName.Equals("discord", StringComparison.OrdinalIgnoreCase) ? "Discord" :
        processName.Equals("teams", StringComparison.OrdinalIgnoreCase) ? "Microsoft Teams" :
        processName;

    private sealed record AudioSessionCandidate(
        int ProcessId,
        string ProcessName,
        string SourceApp,
        string WindowTitle)
    {
        public CallActivitySnapshot ToSnapshot(DateTimeOffset now, string reason) =>
            CallActivitySnapshot.Active(now, SourceApp, reason, ProcessId);
    }
}
