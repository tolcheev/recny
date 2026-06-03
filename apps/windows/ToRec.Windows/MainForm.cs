using System.Drawing;
using System.Windows.Forms;
using ToRec.Windows.Core.Recording;
using ToRec.Windows.Core.Updates;

namespace ToRec.Windows;

public sealed class MainForm : Form
{
    private readonly RecordingController _controller;
    private readonly string _storageRoot;
    private readonly System.Windows.Forms.Timer _timer;
    private readonly Label _statusLabel;
    private readonly Label _elapsedLabel;
    private readonly Button _startButton;
    private readonly Button _stopButton;
    private readonly Button _updatesButton;
    private readonly Button _reportBugButton;
    private readonly string _updateStatePath;
    private AppUpdateReminderState _updateReminderState;
    private AppUpdateRelease? _pendingUpdateRelease;
    private bool _allowClose;

    public MainForm(RecordingController controller, string storageRoot)
    {
        _controller = controller;
        _storageRoot = storageRoot;
        _updateStatePath = Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
            "ToRec",
            "update-state.json");
        _updateReminderState = AppUpdateReminderStore.Load(_updateStatePath);
        Text = "ToRec Windows";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(520, 320);
        Size = new Size(640, 380);

        var title = new Label
        {
            Text = "ToRec",
            Font = new Font(Font.FontFamily, 26, FontStyle.Bold),
            Dock = DockStyle.Top,
            Height = 70,
            TextAlign = ContentAlignment.MiddleCenter
        };

        _statusLabel = new Label
        {
            Dock = DockStyle.Top,
            Height = 36,
            TextAlign = ContentAlignment.MiddleCenter
        };

        _elapsedLabel = new Label
        {
            Dock = DockStyle.Top,
            Height = 52,
            Font = new Font(Font.FontFamily, 24, FontStyle.Bold),
            TextAlign = ContentAlignment.MiddleCenter
        };

        _startButton = new Button
        {
            Text = "Start Recording",
            Width = 180,
            Height = 42
        };
        _startButton.Click += async (_, _) => await RunUiActionAsync(() => _controller.StartAsync());

        _stopButton = new Button
        {
            Text = "Stop Recording",
            Width = 180,
            Height = 42
        };
        _stopButton.Click += async (_, _) => await RunUiActionAsync(() => _controller.StopAsync());

        var recordsButton = new Button
        {
            Text = "Records",
            Width = 120,
            Height = 34
        };
        recordsButton.Click += (_, _) => new RecordsForm(_storageRoot).Show();

        var diagnosticsButton = new Button
        {
            Text = "Diagnostics",
            Width = 120,
            Height = 34
        };
        diagnosticsButton.Click += (_, _) => new DiagnosticsForm(_storageRoot, _controller.LastError).Show();

        _updatesButton = new Button
        {
            Text = "Updates",
            Width = 110,
            Height = 34
        };
        _updatesButton.Click += async (_, _) => await CheckForUpdatesAsync();

        _reportBugButton = new Button
        {
            Text = "Report Bug",
            Width = 110,
            Height = 34
        };
        _reportBugButton.Click += (_, _) => OpenUrl(AppSupportLinks.BugReportUrl(
            AppUpdateChecker.EntryAssemblyDisplayVersion(),
            "windows"));

        var folderButton = new Button
        {
            Text = "Open Folder",
            Width = 120,
            Height = 34
        };
        folderButton.Click += (_, _) => OpenPath(_storageRoot);

        var mainButtons = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 58,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 8, 0, 0)
        };
        mainButtons.Controls.Add(_startButton);
        mainButtons.Controls.Add(_stopButton);

        var secondaryButtons = new FlowLayoutPanel
        {
            Dock = DockStyle.Bottom,
            Height = 86,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = true,
            Padding = new Padding(0, 8, 0, 0)
        };
        secondaryButtons.Controls.Add(recordsButton);
        secondaryButtons.Controls.Add(folderButton);
        secondaryButtons.Controls.Add(diagnosticsButton);
        secondaryButtons.Controls.Add(_updatesButton);
        secondaryButtons.Controls.Add(_reportBugButton);

        var content = new Panel
        {
            Dock = DockStyle.Fill,
            Padding = new Padding(24)
        };
        content.Controls.Add(secondaryButtons);
        content.Controls.Add(mainButtons);
        content.Controls.Add(_elapsedLabel);
        content.Controls.Add(_statusLabel);
        content.Controls.Add(title);

        Controls.Add(content);

        _timer = new System.Windows.Forms.Timer
        {
            Interval = 500
        };
        _timer.Tick += (_, _) => RefreshState();
        _timer.Start();
        _controller.StateChanged += (_, _) => BeginInvoke((MethodInvoker)RefreshState);
        Shown += async (_, _) => await RunAutomaticUpdateCheckAsync();

        RefreshState();
    }

    public void AllowClose()
    {
        _allowClose = true;
    }

    private async Task RunUiActionAsync(Func<Task> action)
    {
        try
        {
            SetButtonsEnabled(false);
            await action();
        }
        catch (Exception ex)
        {
            MessageBox.Show(ex.Message, "ToRec", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
        finally
        {
            RefreshState();
        }
    }

    private void RefreshState()
    {
        if (IsDisposed)
        {
            return;
        }

        _statusLabel.Text = _controller.State switch
        {
            RecordingState.Recording => "Recording microphone + system audio",
            RecordingState.Stopping => "Stopping and finalizing audio files",
            _ => "Auto-start is watching calls. Manual Start is also available."
        };
        _elapsedLabel.Text = _controller.State == RecordingState.Idle
            ? "00:00:00"
            : _controller.Elapsed.ToString(@"hh\:mm\:ss");
        SetButtonsEnabled(true);
    }

    private void SetButtonsEnabled(bool allowActions)
    {
        _startButton.Enabled = allowActions && _controller.State == RecordingState.Idle;
        _stopButton.Enabled = allowActions && _controller.State == RecordingState.Recording;
    }

    private static void OpenPath(string path)
    {
        Directory.CreateDirectory(path);
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path)
        {
            UseShellExecute = true
        });
    }

    private async Task RunAutomaticUpdateCheckAsync()
    {
        var now = DateTimeOffset.UtcNow;
        if (!AppUpdateReminderPolicy.ShouldRunAutomaticCheck(
                now,
                _updateReminderState,
                isRecording: _controller.State == RecordingState.Recording))
        {
            return;
        }

        AppUpdateReminderPolicy.MarkAutomaticCheck(_updateReminderState, now);
        AppUpdateReminderStore.Save(_updateStatePath, _updateReminderState);

        try
        {
            var result = await new AppUpdateChecker().CheckWindowsAsync();
            if (AppUpdateReminderPolicy.ShouldSurfaceUpdate(
                    result,
                    _updateReminderState,
                    DateTimeOffset.UtcNow,
                    isRecording: _controller.State == RecordingState.Recording))
            {
                _pendingUpdateRelease = result.LatestRelease;
                _updatesButton.Text = $"Update {result.LatestRelease.DisplayVersion}";
            }
        }
        catch
        {
            // Automatic checks stay quiet; manual checks show errors.
        }
    }

    private async Task CheckForUpdatesAsync()
    {
        try
        {
            if (_pendingUpdateRelease is not null)
            {
                ShowUpdateDialog(new AppUpdateCheckResult(
                    AppUpdateChecker.EntryAssemblyDisplayVersion(),
                    _pendingUpdateRelease));
                return;
            }

            var result = await new AppUpdateChecker().CheckWindowsAsync();
            if (!result.IsUpdateAvailable)
            {
                MessageBox.Show(result.DisplayText, "ToRec Updates", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            ShowUpdateDialog(result);
        }
        catch (Exception ex)
        {
            MessageBox.Show($"Could not check updates: {ex.Message}", "ToRec Updates", MessageBoxButtons.OK, MessageBoxIcon.Error);
        }
    }

    private void ShowUpdateDialog(AppUpdateCheckResult result)
    {
        var answer = MessageBox.Show(
            $"{result.DisplayText}\n\nYes = download now.\nNo = remind later.\nCancel = skip this version.",
            "ToRec Updates",
            MessageBoxButtons.YesNoCancel,
            MessageBoxIcon.Information);
        if (answer == DialogResult.Yes)
        {
            OpenUrl(result.LatestRelease.DownloadUrl);
        }
        else if (answer == DialogResult.No)
        {
            AppUpdateReminderPolicy.RemindLater(_updateReminderState, result.LatestRelease, DateTimeOffset.UtcNow);
            AppUpdateReminderStore.Save(_updateStatePath, _updateReminderState);
            _pendingUpdateRelease = null;
            _updatesButton.Text = "Updates";
        }
        else if (answer == DialogResult.Cancel)
        {
            AppUpdateReminderPolicy.Skip(_updateReminderState, result.LatestRelease);
            AppUpdateReminderStore.Save(_updateStatePath, _updateReminderState);
            _pendingUpdateRelease = null;
            _updatesButton.Text = "Updates";
        }
    }

    private static void OpenUrl(string url)
    {
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(url)
        {
            UseShellExecute = true
        });
    }

    protected override void OnFormClosing(FormClosingEventArgs e)
    {
        if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
        {
            e.Cancel = true;
            Hide();
            return;
        }

        base.OnFormClosing(e);
    }

    protected override void Dispose(bool disposing)
    {
        if (disposing)
        {
            _timer.Dispose();
        }
        base.Dispose(disposing);
    }
}
