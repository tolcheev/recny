import Foundation

public struct RecordingFinalizationResult: Equatable, Sendable {
    public let status: TaggingStatus
    public let failureReason: String?

    public init(status: TaggingStatus, failureReason: String?) {
        self.status = status
        self.failureReason = failureReason
    }
}

public enum RecordingFinalizationPolicy {
    public static let emptyAudioFileReason = "Empty audio file"
    public static let missingAudioFileReason = "Missing audio file"

    public static func finalize(
        duration: TimeInterval,
        preferredStatus: TaggingStatus,
        shortRecordingThresholdSeconds: TimeInterval,
        requiredTrackKinds: [String],
        audioTracks: [AudioTrackMetadata]
    ) -> RecordingFinalizationResult {
        for requiredTrackKind in requiredTrackKinds {
            let track = audioTracks.first { $0.kind == requiredTrackKind }
            if let failureReason = requiredTrackFailureReason(track) {
                return RecordingFinalizationResult(
                    status: .failed,
                    failureReason: failureReason
                )
            }
        }

        return RecordingFinalizationResult(
            status: TaggingStatus.finalizedStatus(
                forDuration: duration,
                preferredStatus: preferredStatus,
                thresholdSeconds: shortRecordingThresholdSeconds
            ),
            failureReason: nil
        )
    }

    public static func requiredTrackFailureReason(_ track: AudioTrackMetadata?) -> String? {
        guard let track else {
            return missingAudioFileReason
        }

        if let fileSizeBytes = track.fileSizeBytes,
           fileSizeBytes <= 0 {
            return emptyAudioFileReason
        }

        guard track.status == AudioTrackMetadata.completedStatus
            || track.status == AudioTrackMetadata.completedWithWarningsStatus
        else {
            if isEmptyAudioFailureMessage(track.error) {
                return emptyAudioFileReason
            }

            if isMissingAudioFailureMessage(track.error) {
                return missingAudioFileReason
            }

            return track.error?.isEmpty == false ? track.error : "\(track.kind) audio track failed"
        }

        guard let fileSizeBytes = track.fileSizeBytes,
              fileSizeBytes > 0
        else {
            return emptyAudioFileReason
        }

        return nil
    }

    public static func isEmptyAudioFailureMessage(_ message: String?) -> Bool {
        guard let message else {
            return false
        }

        let lowered = message.lowercased()
        return lowered.contains("empty")
            || lowered.contains("no samples")
            || lowered.contains("0 bytes")
    }

    public static func isMissingAudioFailureMessage(_ message: String?) -> Bool {
        guard let message else {
            return false
        }

        return message.lowercased().contains("missing")
    }
}
