using ToRec.Windows.Core.Recording;

namespace ToRec.Windows.Core.Storage;

public static class RecordingMetadataFactory
{
    public static RecordingMetadata Create(
        RecordingSession session,
        DateTimeOffset stoppedAt,
        TimeSpan duration,
        string status,
        AudioPostProcessResult? postProcess,
        string? error,
        string trigger = "manual",
        string sourceApp = "Manual",
        string reason = "")
    {
        var metadata = new RecordingMetadata
        {
            Id = session.Id,
            Status = status,
            Trigger = trigger,
            SourceApp = sourceApp,
            Reason = reason,
            StartedAt = session.StartedAt,
            StoppedAt = stoppedAt,
            DurationSeconds = Math.Round(duration.TotalSeconds, 3),
            SessionFolder = session.SessionDirectory,
            Files = new RecordingMetadataFiles
            {
                MicWav = ExistingRelativeFile(session.SessionDirectory, session.MicWavPath),
                SystemWav = ExistingRelativeFile(session.SessionDirectory, session.SystemWavPath),
                MicM4A = ExistingRelativeFile(session.SessionDirectory, session.MicM4APath),
                SystemM4A = ExistingRelativeFile(session.SessionDirectory, session.SystemM4APath),
                MixedWav = ExistingRelativeFile(session.SessionDirectory, session.MixedWavPath),
                MixedM4A = ExistingRelativeFile(session.SessionDirectory, session.MixedM4APath)
            },
            Error = error
        };

        if (postProcess is not null)
        {
            metadata.Warnings.AddRange(postProcess.Warnings);
        }

        return metadata;
    }

    private static string? ExistingRelativeFile(string sessionDirectory, string path)
    {
        if (!File.Exists(path))
        {
            return null;
        }

        return Path.GetRelativePath(sessionDirectory, path).Replace('\\', '/');
    }
}
