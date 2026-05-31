using System.Reflection;
using System.Runtime.InteropServices;
using NAudio.Wave;

namespace ToRec.Windows.Core.Diagnostics;

public sealed record DiagnosticsSnapshot(
    string AppVersion,
    string OSDescription,
    string RuntimeIdentifier,
    string StorageRoot,
    string NAudioVersion,
    string? LastError
)
{
    public static DiagnosticsSnapshot Create(string storageRoot, string? lastError)
    {
        var appVersion = Assembly.GetEntryAssembly()?.GetName().Version?.ToString() ?? "0.2.2";
        var nAudioVersion = typeof(WaveInEvent).Assembly.GetName().Version?.ToString() ?? "unknown";
        return new DiagnosticsSnapshot(
            appVersion,
            RuntimeInformation.OSDescription,
            RuntimeInformation.RuntimeIdentifier,
            storageRoot,
            nAudioVersion,
            lastError);
    }
}
