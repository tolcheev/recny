import Foundation

public enum RecordingDisplayFormatter {
    public static func statusText(_ status: TaggingStatus) -> String {
        switch status {
        case .needsTagging:
            return "Needs tag"
        case .saved:
            return "Saved"
        case .needsReview:
            return "Needs review"
        case .reviewed:
            return "Reviewed"
        case .failed:
            return "Recording failed"
        case .shortRecording:
            return "Short recording"
        }
    }

    public static func statusSubtitle(_ status: TaggingStatus) -> String? {
        switch status {
        case .needsTagging:
            return "Add a title, participant, or tags when you are ready."
        case .shortRecording:
            return "Saved to Inbox/Short"
        case .failed:
            return "Open Diagnostics for details."
        default:
            return nil
        }
    }

    public static func latestRecordingDetail(
        status: TaggingStatus,
        duration: TimeInterval,
        micFileSizeBytes: Int64?,
        systemFileSizeBytes: Int64?
    ) -> String {
        var parts = [
            Self.duration(duration),
            Self.audioSummary(
                micFileSizeBytes: micFileSizeBytes,
                systemFileSizeBytes: systemFileSizeBytes
            )
        ]

        if let subtitle = statusSubtitle(status) {
            parts.append(subtitle)
        }

        return parts.joined(separator: " · ")
    }

    public static func duration(_ duration: TimeInterval) -> String {
        let totalSeconds = max(0, Int(duration.rounded(.down)))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }

        return String(format: "%02d:%02d", minutes, seconds)
    }

    public static func fileSize(_ value: Int64?) -> String {
        guard let value, value > 0 else {
            return "Missing"
        }

        let kb = Double(value) / 1024
        guard kb >= 1024 else {
            return "\(Int(kb.rounded())) KB"
        }

        let mb = kb / 1024
        let formatted = String(format: "%.1f", mb)
            .replacingOccurrences(of: ".0", with: "")
        return "\(formatted) MB"
    }

    public static func audioSummary(
        micFileSizeBytes: Int64?,
        systemFileSizeBytes: Int64?
    ) -> String {
        let hasMic = (micFileSizeBytes ?? 0) > 0
        let hasSystem = (systemFileSizeBytes ?? 0) > 0

        switch (hasMic, hasSystem) {
        case (true, true):
            return "Mic + system audio"
        case (true, false):
            return "Mic only"
        case (false, true):
            return "System only"
        case (false, false):
            return "No audio"
        }
    }

    public static func microphoneName(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No microphone selected" : trimmed
    }

    public static func systemAudioText(
        isEnabled: Bool,
        captureStatus: CaptureStatus,
        recordingStatus: RecordingStatus
    ) -> String {
        guard isEnabled else {
            return "Off"
        }

        switch captureStatus {
        case .recording:
            return "Active"
        case .permissionDenied:
            return "Needs permission or restart"
        case .error:
            return "System audio error"
        default:
            return recordingStatus == .recording ? "Active" : "Ready"
        }
    }

    public static func humanReadableError(_ errorMessage: String?) -> String {
        guard let errorMessage,
              !errorMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return "Open Diagnostics for details."
        }

        if errorMessage.localizedCaseInsensitiveContains("microphone permission") {
            return "Microphone permission is missing"
        }

        if errorMessage.localizedCaseInsensitiveContains("system audio")
            || errorMessage.localizedCaseInsensitiveContains("screencapturekit")
            || errorMessage.localizedCaseInsensitiveContains("screen & system") {
            return "System audio permission needs app restart or re-approval"
        }

        if errorMessage.localizedCaseInsensitiveContains("input device") {
            return "No microphone input device is available"
        }

        return "Open Diagnostics for details."
    }
}
