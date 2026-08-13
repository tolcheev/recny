using Recny.Windows.Core.Recording;

namespace Recny.Windows.Core.AutoStart;

public sealed class AutoStartDecisionEngine
{
    private readonly AutoStartPolicy _policy;
    private DateTimeOffset? _activeSince;
    private DateTimeOffset? _inactiveSince;
    private string _activeSourceApp = "none";
    private string _activeReason = "No call-like audio.";

    public AutoStartDecisionEngine(AutoStartPolicy policy)
    {
        _policy = policy;
    }

    public AutoStartDecision Evaluate(
        CallActivitySnapshot snapshot,
        RecordingState recordingState,
        string? currentTrigger)
    {
        if (recordingState == RecordingState.Stopping)
        {
            return AutoStartDecision.None;
        }

        if (recordingState == RecordingState.Recording)
        {
            _activeSince = null;

            if (!string.Equals(currentTrigger, "autostart", StringComparison.OrdinalIgnoreCase))
            {
                _inactiveSince = null;
                return AutoStartDecision.None;
            }

            if (snapshot.IsActive)
            {
                _inactiveSince = null;
                return AutoStartDecision.None;
            }

            _inactiveSince ??= snapshot.Timestamp;
            if (snapshot.Timestamp - _inactiveSince.Value >= _policy.StopGraceDuration)
            {
                _inactiveSince = null;
                return new AutoStartDecision(
                    AutoStartActionKind.StopRecording,
                    "none",
                    $"No call-like audio for {_policy.StopGraceDuration.TotalSeconds:0} seconds.");
            }

            return AutoStartDecision.None;
        }

        _inactiveSince = null;

        if (!snapshot.IsActive)
        {
            _activeSince = null;
            _activeSourceApp = "none";
            _activeReason = snapshot.Reason;
            return AutoStartDecision.None;
        }

        if (!string.Equals(_activeSourceApp, snapshot.SourceApp, StringComparison.OrdinalIgnoreCase))
        {
            _activeSince = snapshot.Timestamp;
            _activeSourceApp = snapshot.SourceApp;
        }
        else
        {
            _activeSince ??= snapshot.Timestamp;
        }

        _activeReason = snapshot.Reason;

        if (snapshot.Timestamp - _activeSince.Value >= _policy.StartDetectionDuration)
        {
            _activeSince = null;
            return new AutoStartDecision(
                AutoStartActionKind.StartRecording,
                snapshot.SourceApp,
                $"{snapshot.Reason} Stable for {_policy.StartDetectionDuration.TotalSeconds:0} seconds.",
                snapshot.ProcessId);
        }

        return AutoStartDecision.None;
    }
}
