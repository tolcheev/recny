using System.Text.Json;

namespace ToRec.Windows.Core.Storage;

public static class MetadataWriter
{
    private static readonly JsonSerializerOptions Options = new()
    {
        WriteIndented = true
    };

    public static void Write(string outputPath, RecordingMetadata metadata)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        var json = JsonSerializer.Serialize(metadata, Options);
        File.WriteAllText(outputPath, json);
    }

    public static RecordingMetadata Read(string inputPath)
    {
        var json = File.ReadAllText(inputPath);
        return JsonSerializer.Deserialize<RecordingMetadata>(json, Options)
            ?? throw new InvalidDataException($"Could not parse metadata: {inputPath}");
    }
}
