using System.Diagnostics;
using NAudio.CoreAudioApi;
using NAudio.CoreAudioApi.Interfaces;
using ToRec.Windows.Core.AutoStart;

namespace ToRec.Windows;

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
            using var enumerator = new MMDeviceEnumerator();
            using var renderDevice = enumerator.GetDefaultAudioEndpoint(DataFlow.Render, Role.Multimedia);
            var sessions = renderDevice.AudioSessionManager.Sessions;

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

                var candidate = TryBuildCandidate(now, processId);
                if (candidate is not null)
                {
                    return candidate;
                }
            }
        }
        catch (Exception ex)
        {
            return CallActivitySnapshot.Inactive(now, $"Call activity detection failed: {ex.Message}");
        }

        return CallActivitySnapshot.Inactive(now, "No call-like audio session.");
    }

    private static CallActivitySnapshot? TryBuildCandidate(DateTimeOffset now, int processId)
    {
        try
        {
            using var process = Process.GetProcessById(processId);
            var processName = process.ProcessName;
            var title = process.MainWindowTitle ?? "";

            if (DesktopCallApps.Contains(processName))
            {
                return CallActivitySnapshot.Active(
                    now,
                    NormalizeAppName(processName),
                    $"{NormalizeAppName(processName)} is using system audio.");
            }

            if (Browsers.Contains(processName) && LooksLikeCallWindow(title))
            {
                return CallActivitySnapshot.Active(
                    now,
                    NormalizeAppName(processName),
                    $"{NormalizeAppName(processName)} has a call-like window title: {title}");
            }
        }
        catch
        {
            return null;
        }

        return null;
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
}
