@preconcurrency import AVFoundation
import Foundation

public struct AudioSignalMetadata: Codable, Equatable, Sendable {
    public var hadSignal: Bool
    public var approximateSilenceRatio: Double
    public var clippingDetected: Bool

    public init(
        hadSignal: Bool,
        approximateSilenceRatio: Double,
        clippingDetected: Bool
    ) {
        self.hadSignal = hadSignal
        self.approximateSilenceRatio = min(1, max(0, approximateSilenceRatio))
        self.clippingDetected = clippingDetected
    }

    public static let empty = AudioSignalMetadata(
        hadSignal: false,
        approximateSilenceRatio: 1,
        clippingDetected: false
    )

    enum CodingKeys: String, CodingKey {
        case hadSignal = "had_signal"
        case approximateSilenceRatio = "approximate_silence_ratio"
        case clippingDetected = "clipping_detected"
    }
}

public enum AudioQualityWarningMapper {
    public static let microphoneSilentWarning = "Microphone track seems silent."
    public static let systemSilentWarning = "System audio track seems silent."
    public static let microphoneClippingWarning = "Microphone is clipping."
    public static let systemTrackTruncatedWarning = "System audio track ended before the recording stopped."

    public static func warnings(for tracks: [AudioTrackMetadata], recordingDuration: TimeInterval? = nil) -> [String] {
        let completedTracks = tracks.filter(\.hasCompletedStatus)
        var warnings: [String] = []

        if isSilent(completedTracks.first(where: { $0.kind == "microphone" })?.signal) {
            warnings.append(microphoneSilentWarning)
        }

        if isSilent(completedTracks.first(where: { $0.kind == "system" })?.signal) {
            warnings.append(systemSilentWarning)
        }

        if completedTracks.first(where: { $0.kind == "microphone" })?.signal?.clippingDetected == true {
            warnings.append(microphoneClippingWarning)
        }

        if isSystemTrackTruncated(
            completedTracks.first(where: { $0.kind == "system" }),
            recordingDuration: recordingDuration
        ) {
            warnings.append(systemTrackTruncatedWarning)
        }

        return warnings
    }

    private static func isSilent(_ signal: AudioSignalMetadata?) -> Bool {
        guard let signal else {
            return false
        }

        return !signal.hadSignal || signal.approximateSilenceRatio >= 0.95
    }

    private static func isSystemTrackTruncated(
        _ track: AudioTrackMetadata?,
        recordingDuration: TimeInterval?
    ) -> Bool {
        guard let recordingDuration,
              recordingDuration >= 60,
              let duration = track?.durationSec,
              duration > 0
        else {
            return false
        }

        let missingSeconds = recordingDuration - duration
        return missingSeconds >= 15 && duration < recordingDuration * 0.9
    }
}

public enum AudioSignalAnalyzer {
    private static let frameCapacity: AVAudioFrameCount = 4_096
    private static let sampleStride = 128
    private static let silenceThreshold: Float = 0.006
    private static let signalThreshold: Float = 0.015
    private static let clippingThreshold: Float = 0.98

    public static func analyze(url: URL) -> AudioSignalMetadata {
        do {
            return try analyzeThrowing(url: url)
        } catch {
            AppLogger.recording.error("Audio signal analysis failed for \(url.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
            return .empty
        }
    }

    private static func analyzeThrowing(url: URL) throws -> AudioSignalMetadata {
        let file = try AVAudioFile(forReading: url)
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity)
        else {
            return .empty
        }

        var totalSamples = 0
        var silentSamples = 0
        var signalSamples = 0
        var clippingDetected = false

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameCapacity)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else {
                break
            }

            let channelCount = Int(buffer.format.channelCount)
            guard channelCount > 0, let channelData = buffer.floatChannelData else {
                totalSamples += max(1, frameLength / sampleStride)
                silentSamples += max(1, frameLength / sampleStride)
                continue
            }

            for frameIndex in stride(from: 0, to: frameLength, by: sampleStride) {
                var peak: Float = 0
                for channelIndex in 0..<channelCount {
                    peak = max(peak, abs(channelData[channelIndex][frameIndex]))
                }

                if peak < silenceThreshold {
                    silentSamples += 1
                }

                if peak >= signalThreshold {
                    signalSamples += 1
                }

                if peak >= clippingThreshold {
                    clippingDetected = true
                }

                totalSamples += 1
            }
        }

        guard totalSamples > 0 else {
            return .empty
        }

        let silenceRatio = Double(silentSamples) / Double(totalSamples)
        return AudioSignalMetadata(
            hadSignal: signalSamples > 0 && silenceRatio < 0.98,
            approximateSilenceRatio: silenceRatio,
            clippingDetected: clippingDetected
        )
    }
}
