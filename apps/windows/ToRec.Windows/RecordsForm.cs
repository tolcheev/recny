using System.Drawing;
using System.Windows.Forms;
using ToRec.Windows.Core.Storage;

namespace ToRec.Windows;

public sealed class RecordsForm : Form
{
    private readonly string _storageRoot;
    private readonly ListView _list;
    private readonly Button _playButton;
    private readonly Button _openButton;
    private IReadOnlyList<RecordingMetadata> _recordings = [];

    public RecordsForm(string storageRoot)
    {
        _storageRoot = storageRoot;
        Text = "ToRec Records";
        StartPosition = FormStartPosition.CenterScreen;
        MinimumSize = new Size(780, 420);
        Size = new Size(900, 560);

        _list = new ListView
        {
            Dock = DockStyle.Fill,
            FullRowSelect = true,
            View = View.Details,
            MultiSelect = false
        };
        _list.Columns.Add("Started", 170);
        _list.Columns.Add("Duration", 90);
        _list.Columns.Add("Status", 170);
        _list.Columns.Add("Files", 260);
        _list.SelectedIndexChanged += (_, _) => UpdateButtons();
        _list.DoubleClick += (_, _) => PlaySelected();

        _playButton = new Button
        {
            Text = "Play",
            Width = 100
        };
        _playButton.Click += (_, _) => PlaySelected();

        _openButton = new Button
        {
            Text = "Open Folder",
            Width = 120
        };
        _openButton.Click += (_, _) => OpenSelectedFolder();

        var refreshButton = new Button
        {
            Text = "Refresh",
            Width = 100
        };
        refreshButton.Click += (_, _) => Reload();

        var controls = new FlowLayoutPanel
        {
            Dock = DockStyle.Top,
            Height = 48,
            FlowDirection = FlowDirection.LeftToRight,
            Padding = new Padding(8)
        };
        controls.Controls.Add(_playButton);
        controls.Controls.Add(_openButton);
        controls.Controls.Add(refreshButton);

        Controls.Add(_list);
        Controls.Add(controls);

        Reload();
    }

    private void Reload()
    {
        _recordings = RecordingScanner.Scan(_storageRoot);
        _list.Items.Clear();
        foreach (var recording in _recordings)
        {
            var item = new ListViewItem(recording.StartedAt.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss"))
            {
                Tag = recording
            };
            item.SubItems.Add(TimeSpan.FromSeconds(recording.DurationSeconds).ToString(@"hh\:mm\:ss"));
            item.SubItems.Add(recording.Status);
            item.SubItems.Add(FileSummary(recording));
            _list.Items.Add(item);
        }
        UpdateButtons();
    }

    private void UpdateButtons()
    {
        var selected = SelectedRecording();
        _openButton.Enabled = selected is not null && Directory.Exists(selected.SessionFolder);
        _playButton.Enabled = PreferredAudioPath(selected) is not null;
    }

    private RecordingMetadata? SelectedRecording()
    {
        if (_list.SelectedItems.Count == 0)
        {
            return null;
        }

        return _list.SelectedItems[0].Tag as RecordingMetadata;
    }

    private void PlaySelected()
    {
        var path = PreferredAudioPath(SelectedRecording());
        if (path is null)
        {
            MessageBox.Show("No playable audio file found.", "ToRec", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }

        OpenPath(path);
    }

    private void OpenSelectedFolder()
    {
        var selected = SelectedRecording();
        if (selected is null)
        {
            return;
        }

        OpenPath(selected.SessionFolder);
    }

    private static string FileSummary(RecordingMetadata metadata)
    {
        var names = new[]
        {
            metadata.Files.MixedM4A,
            metadata.Files.MixedWav,
            metadata.Files.MicWav,
            metadata.Files.SystemWav
        };
        return string.Join(", ", names.Where(name => !string.IsNullOrWhiteSpace(name)).Select(Path.GetFileName));
    }

    private static string? PreferredAudioPath(RecordingMetadata? metadata)
    {
        if (metadata is null)
        {
            return null;
        }

        var candidates = new[]
        {
            metadata.Files.MixedM4A,
            metadata.Files.MixedWav,
            metadata.Files.MicM4A,
            metadata.Files.MicWav,
            metadata.Files.SystemM4A,
            metadata.Files.SystemWav
        };

        foreach (var relativePath in candidates)
        {
            if (string.IsNullOrWhiteSpace(relativePath))
            {
                continue;
            }

            var path = Path.Combine(metadata.SessionFolder, relativePath.Replace('/', Path.DirectorySeparatorChar));
            if (File.Exists(path))
            {
                return path;
            }
        }

        return null;
    }

    private static void OpenPath(string path)
    {
        System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(path)
        {
            UseShellExecute = true
        });
    }
}
