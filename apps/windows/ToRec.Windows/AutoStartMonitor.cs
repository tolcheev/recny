using ToRec.Windows.Core.AutoStart;
using ToRec.Windows.Core.Recording;

namespace ToRec.Windows;

public sealed class AutoStartMonitor : IDisposable
{
    private readonly RecordingController _controller;
    private readonly WindowsCallActivityDetector _detector;
    private readonly AutoStartDecisionEngine _engine;
    private readonly FileLogger _logger;
    private readonly System.Threading.Timer _timer;
    private readonly SemaphoreSlim _pollLock = new(1, 1);
    private string _lastReason = "";
    private bool _disposed;

    public AutoStartMonitor(RecordingController controller, FileLogger logger)
    {
        _controller = controller;
        _logger = logger;
        _detector = new WindowsCallActivityDetector();
        _engine = new AutoStartDecisionEngine(AutoStartPolicy.Default);
        _timer = new System.Threading.Timer(_ => _ = PollAsync(), null, TimeSpan.Zero, TimeSpan.FromSeconds(1));
    }

    private async Task PollAsync()
    {
        if (_disposed || !await _pollLock.WaitAsync(0).ConfigureAwait(false))
        {
            return;
        }

        try
        {
            var snapshot = _detector.Capture();
            if (!string.Equals(_lastReason, snapshot.Reason, StringComparison.Ordinal))
            {
                _lastReason = snapshot.Reason;
                _logger.Write($"autostart observation active={snapshot.IsActive} source={snapshot.SourceApp} reason={snapshot.Reason}");
            }

            var decision = _engine.Evaluate(snapshot, _controller.State, _controller.CurrentTrigger);
            if (decision.Action == AutoStartActionKind.StartRecording)
            {
                _logger.Write($"autostart start decision source={decision.SourceApp} reason={decision.Reason}");
                await _controller.StartAsync(
                    trigger: "autostart",
                    sourceApp: decision.SourceApp,
                    reason: decision.Reason).ConfigureAwait(false);
            }
            else if (decision.Action == AutoStartActionKind.StopRecording && _controller.State == RecordingState.Recording)
            {
                _logger.Write($"autostart stop decision reason={decision.Reason}");
                await _controller.StopAsync().ConfigureAwait(false);
            }
        }
        catch (Exception ex)
        {
            _logger.Write($"autostart poll failed error={ex}");
        }
        finally
        {
            _pollLock.Release();
        }
    }

    public void Dispose()
    {
        _disposed = true;
        _timer.Dispose();
        _pollLock.Dispose();
    }
}
