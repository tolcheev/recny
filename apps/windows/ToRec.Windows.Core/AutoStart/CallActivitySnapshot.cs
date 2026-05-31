namespace ToRec.Windows.Core.AutoStart;

public sealed record CallActivitySnapshot(
    DateTimeOffset Timestamp,
    bool IsActive,
    string SourceApp,
    string Reason,
    int? ProcessId = null
)
{
    public static CallActivitySnapshot Active(DateTimeOffset timestamp, string sourceApp, string reason, int? processId = null) =>
        new(timestamp, true, sourceApp, reason, processId);

    public static CallActivitySnapshot Inactive(DateTimeOffset timestamp, string reason) =>
        new(timestamp, false, "none", reason);
}
