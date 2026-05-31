using System.Diagnostics;
using NAudio.Wave;
using ToRec.Windows.Core.Storage;

namespace ToRec.Windows.Core.Recording;

public sealed class RecordingController : IDisposable
{
    private readonly string _storageRoot;
    private readonly Action<string> _log;
    private readonly object _sync = new();
    private readonly Stopwatch _elapsed = new();
    private WaveAudioTrackRecorder? _micRecorder;
    private WaveAudioTrackRecorder? _systemRecorder;

    public RecordingController(string storageRoot, Action<string> log)
    {
        _storageRoot = storageRoot;
        _log = log;
    }

    public RecordingState State { get; private set; } = RecordingState.Idle;
    public RecordingSession? CurrentSession { get; private set; }
    public string? CurrentTrigger { get; private set; }
    public string? CurrentSourceApp { get; private set; }
    public string? CurrentReason { get; private set; }
    public int? CurrentSourceProcessId { get; private set; }
    public string? LastError { get; private set; }
    public TimeSpan Elapsed => _elapsed.Elapsed;

    public event EventHandler? StateChanged;

    public Task<RecordingSession> StartAsync(
        string trigger = "manual",
        string sourceApp = "Manual",
        string reason = "Manual start.",
        int? sourceProcessId = null,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();

        lock (_sync)
        {
            if (State != RecordingState.Idle)
            {
                throw new InvalidOperationException("Recording is already active.");
            }

            LastError = null;
            var session = RecordingPaths.CreateSession(_storageRoot);
            Directory.CreateDirectory(session.SourceDirectory);
            Directory.CreateDirectory(session.ExportDirectory);

            try
            {
                _log($"recording start requested id={session.Id}");

                _micRecorder = new WaveAudioTrackRecorder(new WaveInEvent
                {
                    WaveFormat = new WaveFormat(48_000, 1)
                });
                _systemRecorder = new WaveAudioTrackRecorder(new WasapiLoopbackCapture());

                _micRecorder.Start(session.MicWavPath);
                _systemRecorder.Start(session.SystemWavPath);

                CurrentSession = session;
                CurrentTrigger = trigger;
                CurrentSourceApp = sourceApp;
                CurrentReason = reason;
                CurrentSourceProcessId = sourceProcessId;
                State = RecordingState.Recording;
                _elapsed.Restart();
                _log($"recording started id={session.Id} trigger={trigger} source={sourceApp} processId={sourceProcessId?.ToString() ?? "none"} reason={reason} dir={session.SessionDirectory}");
            }
            catch (Exception ex)
            {
                LastError = ex.Message;
                _log($"recording start failed error={ex}");
                DisposeTrackRecorders();
                CurrentTrigger = null;
                CurrentSourceApp = null;
                CurrentReason = null;
                CurrentSourceProcessId = null;
                State = RecordingState.Idle;
                throw;
            }
        }

        OnStateChanged();
        return Task.FromResult(CurrentSession!);
    }

    public async Task<RecordingSession?> StopAsync(CancellationToken cancellationToken = default)
    {
        RecordingSession? session;
        WaveAudioTrackRecorder? mic;
        WaveAudioTrackRecorder? system;

        lock (_sync)
        {
            if (State != RecordingState.Recording || CurrentSession is null)
            {
                return null;
            }

            State = RecordingState.Stopping;
            session = CurrentSession;
            mic = _micRecorder;
            system = _systemRecorder;
            _log($"recording stop requested id={session.Id}");
        }

        OnStateChanged();

        var stoppedAt = DateTimeOffset.Now;
        var duration = _elapsed.Elapsed;
        var status = "completed";
        string? error = null;
        AudioPostProcessResult? postProcess = null;

        try
        {
            if (mic is not null)
            {
                await mic.StopAsync(TimeSpan.FromSeconds(10), cancellationToken).ConfigureAwait(false);
            }
            if (system is not null)
            {
                await system.StopAsync(TimeSpan.FromSeconds(10), cancellationToken).ConfigureAwait(false);
            }

            postProcess = AudioPostProcessor.Process(session, _log);
            if (postProcess.Warnings.Count > 0 || !postProcess.MixedWavCreated)
            {
                status = "completed_with_warnings";
            }
        }
        catch (Exception ex)
        {
            status = "failed";
            error = ex.Message;
            LastError = ex.Message;
            _log($"recording stop failed id={session.Id} error={ex}");
        }
        finally
        {
            DisposeTrackRecorders();
            _elapsed.Stop();
        }

        var metadata = RecordingMetadataFactory.Create(
            session,
            stoppedAt,
            duration,
            status,
            postProcess,
            error,
            CurrentTrigger ?? "manual",
            CurrentSourceApp ?? "Manual",
            CurrentReason ?? "");
        MetadataWriter.Write(session.MetadataPath, metadata);
        _log($"metadata written id={session.Id} status={status}");

        lock (_sync)
        {
            CurrentSession = null;
            CurrentTrigger = null;
            CurrentSourceApp = null;
            CurrentReason = null;
            CurrentSourceProcessId = null;
            State = RecordingState.Idle;
        }

        OnStateChanged();
        return session;
    }

    private void DisposeTrackRecorders()
    {
        _micRecorder?.Dispose();
        _systemRecorder?.Dispose();
        _micRecorder = null;
        _systemRecorder = null;
    }

    private void OnStateChanged() => StateChanged?.Invoke(this, EventArgs.Empty);

    public void Dispose()
    {
        DisposeTrackRecorders();
    }
}
