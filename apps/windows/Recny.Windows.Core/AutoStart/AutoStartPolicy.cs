namespace Recny.Windows.Core.AutoStart;

public sealed record AutoStartPolicy(
    TimeSpan StartDetectionDuration,
    TimeSpan StopGraceDuration
)
{
    public static AutoStartPolicy Default { get; } = new(
        StartDetectionDuration: TimeSpan.FromSeconds(10),
        StopGraceDuration: TimeSpan.FromSeconds(10));
}
