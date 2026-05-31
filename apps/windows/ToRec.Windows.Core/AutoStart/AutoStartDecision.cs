namespace ToRec.Windows.Core.AutoStart;

public enum AutoStartActionKind
{
    None,
    StartRecording,
    StopRecording
}

public sealed record AutoStartDecision(
    AutoStartActionKind Action,
    string SourceApp,
    string Reason
)
{
    public static AutoStartDecision None { get; } = new(AutoStartActionKind.None, "none", "No action.");
}
