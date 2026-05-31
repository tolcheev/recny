namespace ToRec.Windows.Core.AutoStart;

public sealed record CallActivitySnapshot(
    DateTimeOffset Timestamp,
    bool IsActive,
    string SourceApp,
    string Reason
)
{
    public static CallActivitySnapshot Active(DateTimeOffset timestamp, string sourceApp, string reason) =>
        new(timestamp, true, sourceApp, reason);

    public static CallActivitySnapshot Inactive(DateTimeOffset timestamp, string reason) =>
        new(timestamp, false, "none", reason);
}
