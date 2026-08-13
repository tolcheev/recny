namespace Recny.Windows.Core.Storage;

public static class RecordingScanner
{
    public static IReadOnlyList<RecordingMetadata> Scan(string storageRoot)
    {
        var libraryRoot = Path.Combine(storageRoot, "Library");
        if (!Directory.Exists(libraryRoot))
        {
            return [];
        }

        var recordings = new List<RecordingMetadata>();
        foreach (var metadataPath in Directory.EnumerateFiles(libraryRoot, "metadata.json", SearchOption.AllDirectories))
        {
            try
            {
                var metadata = MetadataWriter.Read(metadataPath);
                if (string.IsNullOrWhiteSpace(metadata.SessionFolder))
                {
                    metadata.SessionFolder = Path.GetDirectoryName(metadataPath) ?? "";
                }
                recordings.Add(metadata);
            }
            catch
            {
                // A broken metadata file should not hide the rest of the local library.
            }
        }

        return recordings
            .OrderByDescending(recording => recording.StartedAt)
            .ToList();
    }
}
