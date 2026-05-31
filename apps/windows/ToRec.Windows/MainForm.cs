using System.Drawing;
using System.Windows.Forms;
using ToRec.Windows.Core.Recording;

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
    private bool _allowClose;

    public MainForm(RecordingController controller, string storageRoot)
    {
        _controller = controller;
        _storageRoot = storageRoot;
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
            Height = 54,
            FlowDirection = FlowDirection.LeftToRight,
            WrapContents = false,
            Padding = new Padding(0, 8, 0, 0)
        };
        secondaryButtons.Controls.Add(recordsButton);
        secondaryButtons.Controls.Add(folderButton);
        secondaryButtons.Controls.Add(diagnosticsButton);

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
            _ => "Ready. Start manually before the call."
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
