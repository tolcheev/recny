namespace Recny.Windows.Core.Recording;

public sealed record RecordingSession(
    string Id,
    DateTimeOffset StartedAt,
    string SessionDirectory,
    string SourceDirectory,
    string ExportDirectory,
    string MicWavPath,
    string SystemWavPath,
    string MicM4APath,
    string SystemM4APath,
    string MixedWavPath,
    string MixedM4APath,
    string MetadataPath
);
