using System.Windows.Forms;
using ToRec.Windows.Core.Recording;
using ToRec.Windows.Core.Updates;

namespace ToRec.Windows;

public sealed class TrayAppContext : ApplicationContext
{
    private readonly RecordingController _controller;
    private readonly string _storageRoot;
    private readonly FileLogger _logger;
    private readonly AutoStartMonitor _autoStartMonitor;
    private readonly NotifyIcon _notifyIcon;
    private readonly ToolStripMenuItem _startItem;
    private readonly ToolStripMenuItem _stopItem;
    private MainForm? _mainForm;

    public TrayAppContext(RecordingController controller, string storageRoot, FileLogger logger)
    {
        _controller = controller;
        _storageRoot = storageRoot;
        _logger = logger;
        _controller.StateChanged += OnStateChanged;
        _autoStartMonitor = new AutoStartMonitor(_controller, _logger);

        _startItem = new ToolStripMenuItem("Start Recording", null, async (_, _) => await StartRecordingAsync());
        _stopItem = new ToolStripMenuItem("Stop Recording", null, async (_, _) => await StopRecordingAsync());

        var menu = new ContextMenuStrip();
        menu.Items.Add("Show", null, (_, _) => ShowMainWindow());
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Auto-start: On", null, (_, _) => ShowMainWindow()).Enabled = false;
        menu.Items.Add(_startItem);
        menu.Items.Add(_stopItem);
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Records", null, (_, _) => new RecordsForm(_storageRoot).Show());
        menu.Items.Add("Open Records Folder", null, (_, _) => OpenPath(_storageRoot));
        menu.Items.Add("Diagnostics", null, (_, _) => new DiagnosticsForm(_storageRoot, _controller.LastError).Show());
        menu.Items.Add("Check for Updates", null, async (_, _) => await CheckForUpdatesAsync());
        menu.Items.Add("Report Bug", null, (_, _) => OpenUrl(AppSupportLinks.BugReportUrl(
            AppUpdateChecker.EntryAssemblyDisplayVersion(),
            "windows")));
        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Exit", null, async (_, _) => await ExitAsync());

        _notifyIcon = new NotifyIcon
        {
            ContextMenuStrip = menu,
            Icon = TrayIconFactory.Create(false),
            Text = "ToRec",
            Visible = true
        };
        _notifyIcon.DoubleClick += (_, _) => ShowMainWindow();

        UpdateMenu();
        ShowMainWindow();
    }

    private async Task StartRecordingAsync()
    {
        try
        {
            await _controller.StartAsync();
        }
        catch (Exception ex)
        {
            _logger.Write($"start from tray failed error={ex}");
            MessageBox.Show(ex.Message, "ToRec start failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private async Task StopRecordingAsync()
    {
        try
        {
            await _controller.StopAsync();
        }
        catch (Exception ex)
        {
            _logger.Write($"stop from tray failed error={ex}");
            MessageBox.Show(ex.Message, "ToRec stop failed", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ShowMainWindow()
    {
        if (_mainForm is null || _mainForm.IsDisposed)
        {
            _mainForm = new MainForm(_controller, _storageRoot);
        }

        _mainForm.Show();
        _mainForm.WindowState = FormWindowState.Normal;
        _mainForm.Activate();
    }

    private void OnStateChanged(object? sender, EventArgs args)
    {
        var form = Application.OpenForms.Count > 0 ? Application.OpenForms[0] : null;
        if (form is not null && !form.IsDisposed)
        {
            form.BeginInvoke((MethodInvoker)UpdateMenu);
        }
        else
        {
            UpdateMenu();
        }
    }

    private void UpdateMenu()
    {
        var isRecording = _controller.State == RecordingState.Recording;
        _startItem.Enabled = _controller.State == RecordingState.Idle;
        _stopItem.Enabled = isRecording;
        _notifyIcon.Text = isRecording ? "ToRec is recording" : "ToRec";
        var oldIcon = _notifyIcon.Icon;
        _notifyIcon.Icon = TrayIconFactory.Create(isRecording);
        oldIcon?.Dispose();
    }

    private static void OpenPath(string path)
    {
        Directory.CreateDirectory(path);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path)
        {
            UseShellExecute = true
        });
    }

    private static async Task CheckForUpdatesAsync()
    {
        try
        {
            var result = await new AppUpdateChecker().CheckWindowsAsync();
            if (!result.IsUpdateAvailable)
            {
                MessageBox.Show(result.DisplayText, "ToRec Updates", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            var answer = MessageBox.Show(
                $"{result.DisplayText}\n\nOpen the download page now?",
                "ToRec Updates",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Information);
            if (answer == DialogResult.Yes)
            {
                OpenUrl(result.LatestRelease.DownloadUrl);
            }
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Could not check updates: {ex.Message}", "ToRec Updates", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private static void OpenUrl(string url)
    {
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url)
        {
            UseShellExecute = true
        });
    }

    private async Task ExitAsync()
    {
        if (_controller.State == RecordingState.Recording)
        {
            var result = MessageBox.Show(
                "A recording is active. Stop it and exit?",
                "ToRec",
                MessageBoxButtons.YesNo,
                MessageBoxIcon.Warning);
            if (result != DialogResult.Yes)
            {
                return;
            }

            await _controller.StopAsync();
        }

        _notifyIcon.Visible = false;
        _notifyIcon.Dispose();
        _autoStartMonitor.Dispose();
        _mainForm?.AllowClose();
        Application.Exit();
    }
}
