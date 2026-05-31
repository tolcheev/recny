using System.Drawing;
using System.Windows.Forms;
using ToRec.Windows.Core.Diagnostics;

namespace ToRec.Windows;

public sealed class DiagnosticsForm : Form
{
    public DiagnosticsForm(string storageRoot, string? lastError)
    {
        Text = "ToRec Diagnostics";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(640, 420);
        Size = new Size(760, 520);

        var snapshot = DiagnosticsSnapshot.Create(storageRoot, lastError);
        var logPath = Path.Combine(storageRoot, "logs", "app.log");

        var text = new TextBox
        {
            Dock = DockStyle.Fill,
            Multiline = true,
            ReadOnly = true,
            ScrollBars = ScrollBars.Both,
            Font = new Font(FontFamily.GenericMonospace, 10),
            Text = string.Join(Environment.NewLine, new[]
            {
                $"App version: {snapshot.AppVersion}",
                $"OS: {snapshot.OSDescription}",
                $"Runtime: {snapshot.RuntimeIdentifier}",
                $"NAudio: {snapshot.NAudioVersion}",
                $"Storage root: {snapshot.StorageRoot}",
                $"Log path: {logPath}",
                $"Last error: {snapshot.LastError ?? "none"}"
            })
        };

        var openLogsButton = new Button
        {
            Dock = DockStyle.Bottom,
            Height = 40,
            Text = "Open Logs Folder"
        };
        openLogsButton.Click += (_, _) => OpenPath(Path.GetDirectoryName(logPath)!);

        Controls.Add(text);
        Controls.Add(openLogsButton);
    }

    private static void OpenPath(string path)
    {
        Directory.CreateDirectory(path);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path)
        {
            UseShellExecute = true
        });
    }
}
