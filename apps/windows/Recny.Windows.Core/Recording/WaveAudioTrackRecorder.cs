using NAudio.Wave;

namespace Recny.Windows.Core.Recording;

public sealed class WaveAudioTrackRecorder : IDisposable
{
    private readonly IWaveIn _capture;
    private readonly object _sync = new();
    private WaveFileWriter? _writer;
    private TaskCompletionSource<Exception?>? _stopped;
    private bool _started;

    public WaveAudioTrackRecorder(IWaveIn capture)
    {
        _capture = capture;
    }

    public void Start(string outputPath)
    {
        if (_started)
        {
            throw new InvalidOperationException("Track recorder is already started.");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(outputPath)!);
        _writer = new WaveFileWriter(outputPath, _capture.WaveFormat);
        _stopped = new TaskCompletionSource<Exception?>(TaskCreationOptions.RunContinuationsAsynchronously);

        _capture.DataAvailable += OnDataAvailable;
        _capture.RecordingStopped += OnRecordingStopped;

        try
        {
            _capture.StartRecording();
            _started = true;
        }
        catch
        {
            _capture.DataAvailable -= OnDataAvailable;
            _capture.RecordingStopped -= OnRecordingStopped;
            lock (_sync)
            {
                _writer?.Dispose();
                _writer = null;
            }
            throw;
        }
    }

    public async Task StopAsync(TimeSpan timeout, CancellationToken cancellationToken = default)
    {
        if (!_started)
        {
            return;
        }

        var stopped = _stopped;
        if (stopped is null)
        {
            return;
        }

        _capture.StopRecording();
        var completed = await Task.WhenAny(stopped.Task, Task.Delay(timeout, cancellationToken)).ConfigureAwait(false);
        if (completed != stopped.Task)
        {
            throw new TimeoutException("Timed out while stopping audio capture.");
        }

        var error = await stopped.Task.ConfigureAwait(false);
        if (error is not null)
        {
            throw error;
        }
    }

    private void OnDataAvailable(object? sender, WaveInEventArgs args)
    {
        lock (_sync)
        {
            _writer?.Write(args.Buffer, 0, args.BytesRecorded);
            _writer?.Flush();
        }
    }

    private void OnRecordingStopped(object? sender, StoppedEventArgs args)
    {
        _capture.DataAvailable -= OnDataAvailable;
        _capture.RecordingStopped -= OnRecordingStopped;

        lock (_sync)
        {
            _writer?.Dispose();
            _writer = null;
        }

        _started = false;
        _stopped?.TrySetResult(args.Exception);
    }

    public void Dispose()
    {
        _capture.DataAvailable -= OnDataAvailable;
        _capture.RecordingStopped -= OnRecordingStopped;
        lock (_sync)
        {
            _writer?.Dispose();
            _writer = null;
        }
        _capture.Dispose();
    }
}
