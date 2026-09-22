namespace Recny.Windows.Core.Recording;

public sealed class AudioPostProcessResult
{
    public bool MixedWavCreated { get; init; }
    public bool MicM4ACreated { get; init; }
    public bool SystemM4ACreated { get; init; }
    public bool MixedM4ACreated { get; init; }
    public List<string> Warnings { get; } = [];
}
