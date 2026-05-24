import Foundation

public enum AudioHealthStatus: String, Codable, CaseIterable, Sendable {
    case good
    case warning
    case failed
}

public enum AudioHealthWarning: String, Codable, CaseIterable, Identifiable, Sendable {
    case micSilent = "mic_silent"
    case systemSilent = "system_silent"
    case micTooQuiet = "mic_too_quiet"
    case systemTooQuiet = "system_too_quiet"
    case clippingDetected = "clipping_detected"
    case balancedMixFailed = "balanced_mix_failed"
    case onlyOneTrackAvailable = "only_one_track_available"

    public var id: String {
        rawValue
    }
}

public struct AudioHealthMetadata: Codable, Equatable, Sendable {
    public var status: AudioHealthStatus
    public var warnings: [AudioHealthWarning]

    public init(
        status: AudioHealthStatus = .good,
        warnings: [AudioHealthWarning] = []
    ) {
        self.status = status
        self.warnings = Self.orderedUnique(warnings)
    }

    public static let good = AudioHealthMetadata()

    private static func orderedUnique(_ warnings: [AudioHealthWarning]) -> [AudioHealthWarning] {
        AudioHealthWarning.allCases.filter { warning in
            warnings.contains(warning)
        }
    }
}

public enum AudioHealthEvaluator {
    public static let quietLoudnessThresholdDB = -42.0

    public static func evaluate(
        audioTracks: [AudioTrackMetadata],
        processing: AudioProcessingMetadata = .skipped,
        microphoneAnalysis: AudioLevelAnalysis? = nil,
        systemAnalysis: AudioLevelAnalysis? = nil
    ) -> AudioHealthMetadata {
        let microphoneTrack = audioTracks.first { $0.kind == "microphone" }
        let systemTrack = audioTracks.first { $0.kind == "system" }
        let microphoneAvailable = isTrackAvailable(microphoneTrack, analysis: microphoneAnalysis)
        let systemAvailable = isTrackAvailable(systemTrack, analysis: systemAnalysis)

        var warnings: [AudioHealthWarning] = []

        if microphoneAvailable || systemAvailable {
            if microphoneAvailable != systemAvailable {
                warnings.append(.onlyOneTrackAvailable)
            }
        }

        if isSilent(track: microphoneTrack, analysis: microphoneAnalysis) {
            warnings.append(.micSilent)
        }

        if isSilent(track: systemTrack, analysis: systemAnalysis) {
            warnings.append(.systemSilent)
        }

        if isTooQuiet(analysis: microphoneAnalysis) {
            warnings.append(.micTooQuiet)
        }

        if isTooQuiet(analysis: systemAnalysis) {
            warnings.append(.systemTooQuiet)
        }

        if isClipping(track: microphoneTrack, analysis: microphoneAnalysis)
            || isClipping(track: systemTrack, analysis: systemAnalysis) {
            warnings.append(.clippingDetected)
        }

        if processing.balancedMixStatus == .failed {
            warnings.append(.balancedMixFailed)
        }

        let status: AudioHealthStatus
        if !microphoneAvailable && !systemAvailable {
            status = .failed
            warnings.removeAll { $0 == .onlyOneTrackAvailable }
        } else if warnings.isEmpty {
            status = .good
        } else {
            status = .warning
        }

        return AudioHealthMetadata(status: status, warnings: warnings)
    }

    private static func isTrackAvailable(
        _ track: AudioTrackMetadata?,
        analysis: AudioLevelAnalysis?
    ) -> Bool {
        if let analysis, analysis.exists {
            return analysis.fileSizeBytes > 0
        }

        guard let track,
              track.status == "completed",
              (track.fileSizeBytes ?? 0) > 0
        else {
            return false
        }

        return true
    }

    private static func isSilent(
        track: AudioTrackMetadata?,
        analysis: AudioLevelAnalysis?
    ) -> Bool {
        if let analysis, analysis.exists {
            return !analysis.hasUsableSignal || analysis.silenceRatio >= 0.95
        }

        guard let signal = track?.signal else {
            return false
        }

        return !signal.hadSignal || signal.approximateSilenceRatio >= 0.95
    }

    private static func isTooQuiet(analysis: AudioLevelAnalysis?) -> Bool {
        guard let analysis,
              analysis.exists,
              analysis.hasUsableSignal,
              analysis.silenceRatio < 0.95
        else {
            return false
        }

        return analysis.approximateLoudnessDB <= quietLoudnessThresholdDB
    }

    private static func isClipping(
        track: AudioTrackMetadata?,
        analysis: AudioLevelAnalysis?
    ) -> Bool {
        if let analysis, analysis.exists {
            return analysis.clippingDetected
        }

        return track?.signal?.clippingDetected == true
    }
}
