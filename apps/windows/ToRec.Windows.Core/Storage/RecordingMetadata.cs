using System.Text.Json.Serialization;

namespace ToRec.Windows.Core.Storage;

public sealed class RecordingMetadata
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = "";

    [JsonPropertyName("app")]
    public string App { get; set; } = "ToRec";

    [JsonPropertyName("platform")]
    public string Platform { get; set; } = "windows";

    [JsonPropertyName("version")]
    public string Version { get; set; } = "0.2.0-beta";

    [JsonPropertyName("status")]
    public string Status { get; set; } = "completed";

    [JsonPropertyName("trigger")]
    public string Trigger { get; set; } = "manual";

    [JsonPropertyName("startedAt")]
    public DateTimeOffset StartedAt { get; set; }

    [JsonPropertyName("stoppedAt")]
    public DateTimeOffset StoppedAt { get; set; }

    [JsonPropertyName("durationSeconds")]
    public double DurationSeconds { get; set; }

    [JsonPropertyName("sessionFolder")]
    public string SessionFolder { get; set; } = "";

    [JsonPropertyName("files")]
    public RecordingMetadataFiles Files { get; set; } = new();

    [JsonPropertyName("warnings")]
    public List<string> Warnings { get; set; } = [];

    [JsonPropertyName("error")]
    public string? Error { get; set; }
}

public sealed class RecordingMetadataFiles
{
    [JsonPropertyName("micWav")]
    public string? MicWav { get; set; }

    [JsonPropertyName("systemWav")]
    public string? SystemWav { get; set; }

    [JsonPropertyName("micM4A")]
    public string? MicM4A { get; set; }

    [JsonPropertyName("systemM4A")]
    public string? SystemM4A { get; set; }

    [JsonPropertyName("mixedWav")]
    public string? MixedWav { get; set; }

    [JsonPropertyName("mixedM4A")]
    public string? MixedM4A { get; set; }
}
