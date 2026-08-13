using System.Globalization;
using Recny.Windows.Core.Recording;

namespace Recny.Windows.Core.Storage;

public static class RecordingPaths
{
    public static string DefaultRoot =>
        Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.UserProfile),
            "Recordings",
            // Keep the historical folder so existing local recordings remain available.
            "TOrbitRecorder");

    public static RecordingSession CreateSession(string storageRoot, DateTimeOffset? startedAt = null)
    {
        var started = startedAt ?? DateTimeOffset.Now;
        var timestamp = started.ToString("yyyy-MM-dd_HH-mm-ss", CultureInfo.InvariantCulture);
        var id = $"rec_{timestamp}_{Guid.NewGuid().ToString("N")[..8]}";

        var sessionDirectory = Path.Combine(
            storageRoot,
            "Library",
            started.ToString("yyyy", CultureInfo.InvariantCulture),
            started.ToString("MM", CultureInfo.InvariantCulture),
            id);

        var sourceDirectory = Path.Combine(sessionDirectory, "source");
        var exportDirectory = Path.Combine(sessionDirectory, "export");

        return new RecordingSession(
            id,
            started,
            sessionDirectory,
            sourceDirectory,
            exportDirectory,
            Path.Combine(sourceDirectory, "mic.wav"),
            Path.Combine(sourceDirectory, "system.wav"),
            Path.Combine(sourceDirectory, "mic.m4a"),
            Path.Combine(sourceDirectory, "system.m4a"),
            Path.Combine(exportDirectory, "mixed.wav"),
            Path.Combine(exportDirectory, "mixed.m4a"),
            Path.Combine(sessionDirectory, "metadata.json"));
    }
}
