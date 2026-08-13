@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

public enum AudioLevelTrackKind: String, Codable, Equatable, Sendable {
    case microphone
    case system
    case mixedBalanced = "mixed_balanced"

    public var relativePath: String {
        switch self {
        case .microphone:
            return "source/mic.m4a"
        case .system:
            return "source/system.m4a"
        case .mixedBalanced:
            return "export/mixed_balanced.m4a"
        }
    }
}

public struct AudioLevelAnalysis: Codable, Equatable, Sendable {
    public var kind: AudioLevelTrackKind
    public var relativePath: String
    public var exists: Bool
    public var fileSizeBytes: Int64
    public var durationSec: Double
    public var peakDBFS: Double
    public var rmsDBFS: Double
    public var approximateLoudnessDB: Double
    public var silenceRatio: Double
    public var clippingDetected: Bool
    public var hasUsableSignal: Bool

    public init(
        kind: AudioLevelTrackKind,
        relativePath: String,
        exists: Bool,
        fileSizeBytes: Int64,
        durationSec: Double,
        peakDBFS: Double,
        rmsDBFS: Double,
        approximateLoudnessDB: Double,
        silenceRatio: Double,
        clippingDetected: Bool,
        hasUsableSignal: Bool
    ) {
        self.kind = kind
        self.relativePath = relativePath
        self.exists = exists
        self.fileSizeBytes = max(0, fileSizeBytes)
        self.durationSec = max(0, durationSec)
        self.peakDBFS = peakDBFS
        self.rmsDBFS = rmsDBFS
        self.approximateLoudnessDB = approximateLoudnessDB
        self.silenceRatio = min(1, max(0, silenceRatio))
        self.clippingDetected = clippingDetected
        self.hasUsableSignal = hasUsableSignal
    }

    public static func missing(kind: AudioLevelTrackKind) -> AudioLevelAnalysis {
        AudioLevelAnalysis(
            kind: kind,
            relativePath: kind.relativePath,
            exists: false,
            fileSizeBytes: 0,
            durationSec: 0,
            peakDBFS: -120,
            rmsDBFS: -120,
            approximateLoudnessDB: -120,
            silenceRatio: 1,
            clippingDetected: false,
            hasUsableSignal: false
        )
    }

    enum CodingKeys: String, CodingKey {
        case kind
        case relativePath = "relative_path"
        case exists
        case fileSizeBytes = "file_size_bytes"
        case durationSec = "duration_sec"
        case peakDBFS = "peak_dbfs"
        case rmsDBFS = "rms_dbfs"
        case approximateLoudnessDB = "approx_loudness_db"
        case silenceRatio = "silence_ratio"
        case clippingDetected = "clipping_detected"
        case hasUsableSignal = "has_usable_signal"
    }
}

public final class AudioLevelAnalyzer: Sendable {
    private let frameCapacity: AVAudioFrameCount
    private let sampleStride: Int
    private let silenceThreshold: Float
    private let signalThreshold: Float
    private let clippingThreshold: Float

    public init(
        frameCapacity: AVAudioFrameCount = 4_096,
        sampleStride: Int = 128,
        silenceThreshold: Float = 0.006,
        signalThreshold: Float = 0.015,
        clippingThreshold: Float = 0.98
    ) {
        self.frameCapacity = frameCapacity
        self.sampleStride = max(1, sampleStride)
        self.silenceThreshold = silenceThreshold
        self.signalThreshold = signalThreshold
        self.clippingThreshold = clippingThreshold
    }

    public func analyze(url: URL, kind: AudioLevelTrackKind) throws -> AudioLevelAnalysis {
        let fileSize = try Self.fileSize(at: url)
        guard fileSize > 0 else {
            return .missing(kind: kind)
        }

        let file = try AVAudioFile(forReading: url)
        guard let processingFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: file.processingFormat.sampleRate,
            channels: file.processingFormat.channelCount,
            interleaved: false
        ),
            let buffer = AVAudioPCMBuffer(pcmFormat: processingFormat, frameCapacity: frameCapacity)
        else {
            return .missing(kind: kind)
        }

        var totalSamples = 0
        var silentSamples = 0
        var signalSamples = 0
        var clippingDetected = false
        var peak: Float = 0
        var squareSum: Double = 0

        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: frameCapacity)
            let frameLength = Int(buffer.frameLength)
            guard frameLength > 0 else {
                break
            }

            let channelCount = Int(buffer.format.channelCount)
            guard channelCount > 0, let channelData = buffer.floatChannelData else {
                continue
            }

            for frameIndex in stride(from: 0, to: frameLength, by: sampleStride) {
                var framePeak: Float = 0
                var frameSquare: Double = 0

                for channelIndex in 0..<channelCount {
                    let sample = channelData[channelIndex][frameIndex]
                    let absolute = abs(sample)
                    framePeak = max(framePeak, absolute)
                    frameSquare += Double(sample * sample)
                }

                frameSquare /= Double(channelCount)
                squareSum += frameSquare
                peak = max(peak, framePeak)

                if framePeak < silenceThreshold {
                    silentSamples += 1
                }

                if framePeak >= signalThreshold {
                    signalSamples += 1
                }

                if framePeak >= clippingThreshold {
                    clippingDetected = true
                }

                totalSamples += 1
            }
        }

        guard totalSamples > 0 else {
            return .missing(kind: kind)
        }

        let duration = file.processingFormat.sampleRate > 0
            ? Double(file.length) / file.processingFormat.sampleRate
            : 0
        let silenceRatio = Double(silentSamples) / Double(totalSamples)
        let rms = sqrt(squareSum / Double(totalSamples))
        let peakDBFS = Self.dbfs(Double(peak))
        let rmsDBFS = Self.dbfs(rms)
        let hasUsableSignal = signalSamples > 0
            && silenceRatio < 0.98
            && rmsDBFS > -60

        return AudioLevelAnalysis(
            kind: kind,
            relativePath: kind.relativePath,
            exists: true,
            fileSizeBytes: fileSize,
            durationSec: duration,
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            approximateLoudnessDB: rmsDBFS,
            silenceRatio: silenceRatio,
            clippingDetected: clippingDetected,
            hasUsableSignal: hasUsableSignal
        )
    }

    public func analyzeIfPresent(url: URL, kind: AudioLevelTrackKind) -> AudioLevelAnalysis {
        do {
            let analysis = try analyze(url: url, kind: kind)
            AppLogger.file(
                analysis.exists ? .info : .warning,
                category: "recording",
                "audio level analysis kind=\(kind.rawValue) path=\(url.path(percentEncoded: false)) exists=\(analysis.exists) size=\(analysis.fileSizeBytes) duration=\(String(format: "%.2f", analysis.durationSec)) peak_dbfs=\(String(format: "%.1f", analysis.peakDBFS)) rms_dbfs=\(String(format: "%.1f", analysis.rmsDBFS)) silence_ratio=\(String(format: "%.2f", analysis.silenceRatio)) clipping=\(analysis.clippingDetected) usable=\(analysis.hasUsableSignal)"
            )
            return analysis
        } catch {
            AppLogger.file(.warning, category: "recording", "audio level analysis skipped kind=\(kind.rawValue) path=\(url.path(percentEncoded: false)) error=\(String(describing: error))")
            return .missing(kind: kind)
        }
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let path = url.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else {
            return 0
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func dbfs(_ amplitude: Double) -> Double {
        guard amplitude.isFinite, amplitude > 0 else {
            return -120
        }

        return 20 * log10(max(amplitude, 0.000_001))
    }
}

public enum AudioLevelingMode: String, CaseIterable, Codable, Equatable, Sendable {
    case balanced
    case conservative
    case voiceBoost = "voice_boost"

    public var displayName: String {
        switch self {
        case .balanced:
            return "Balanced"
        case .conservative:
            return "Conservative"
        case .voiceBoost:
            return "Voice Boost"
        }
    }

    public var isImplemented: Bool {
        self != .voiceBoost
    }
}

public enum BalancedMixStatus: String, Codable, Equatable, Sendable {
    case done
    case failed
    case skipped
    case partial
}

public enum AudioLevelingWarning: String, Codable, CaseIterable, Equatable, Sendable {
    case microphoneSeemsSilent = "microphone_track_seems_silent"
    case systemSeemsSilent = "system_audio_track_seems_silent"
    case microphoneClippingDetected = "microphone_clipping_detected"
    case systemClippingDetected = "system_clipping_detected"
    case balancedMixFailed = "balanced_mix_failed"

    public var message: String {
        switch self {
        case .microphoneSeemsSilent:
            return "Microphone track seems silent."
        case .systemSeemsSilent:
            return "System audio track seems silent."
        case .microphoneClippingDetected:
            return "Microphone is clipping."
        case .systemClippingDetected:
            return "System audio is clipping."
        case .balancedMixFailed:
            return "Balanced preview could not be created. Original mix is still available."
        }
    }
}

public struct AudioBalancePlan: Codable, Equatable, Sendable {
    public var microphoneGainDB: Double
    public var systemGainDB: Double
    public var limiterCeilingDBFS: Double
    public var limiterRequired: Bool
    public var status: BalancedMixStatus
    public var usedSourceKinds: [String]
    public var warnings: [AudioLevelingWarning]

    public init(
        microphoneGainDB: Double,
        systemGainDB: Double,
        limiterCeilingDBFS: Double,
        limiterRequired: Bool,
        status: BalancedMixStatus,
        usedSourceKinds: [String],
        warnings: [AudioLevelingWarning]
    ) {
        self.microphoneGainDB = microphoneGainDB
        self.systemGainDB = systemGainDB
        self.limiterCeilingDBFS = limiterCeilingDBFS
        self.limiterRequired = limiterRequired
        self.status = status
        self.usedSourceKinds = usedSourceKinds
        self.warnings = warnings
    }

    enum CodingKeys: String, CodingKey {
        case microphoneGainDB = "mic_gain_db"
        case systemGainDB = "system_gain_db"
        case limiterCeilingDBFS = "limiter_ceiling_dbfs"
        case limiterRequired = "limiter_required"
        case status
        case usedSourceKinds = "used_source_kinds"
        case warnings
    }
}

public struct AudioBalancePlanner: Sendable {
    public var maxGainBoostDB: Double
    public var maxAttenuationDB: Double
    public var limiterCeilingDBFS: Double

    public init(
        maxGainBoostDB: Double = 12,
        maxAttenuationDB: Double = 12,
        limiterCeilingDBFS: Double = -1
    ) {
        self.maxGainBoostDB = max(0, maxGainBoostDB)
        self.maxAttenuationDB = max(0, maxAttenuationDB)
        self.limiterCeilingDBFS = limiterCeilingDBFS
    }

    public func plan(
        microphone: AudioLevelAnalysis?,
        system: AudioLevelAnalysis?,
        mode: AudioLevelingMode
    ) -> AudioBalancePlan {
        let microphoneUsable = isUsable(microphone)
        let systemUsable = isUsable(system)
        let usable: [AudioLevelAnalysis] = [microphone, system]
            .compactMap { $0 }
            .filter { isUsable($0) }
        var warnings = warnings(for: microphone, system: system)

        guard !usable.isEmpty else {
            warnings.append(.balancedMixFailed)
            return AudioBalancePlan(
                microphoneGainDB: 0,
                systemGainDB: 0,
                limiterCeilingDBFS: limiterCeilingDBFS,
                limiterRequired: false,
                status: .failed,
                usedSourceKinds: [],
                warnings: unique(warnings)
            )
        }

        let limits = limits(for: mode)
        let targetLoudness = targetLoudness(for: usable)
        var microphoneGain = gain(
            for: microphone,
            targetLoudness: targetLoudness,
            maxBoost: limits.maxBoost,
            maxAttenuation: limits.maxAttenuation
        )
        var systemGain = gain(
            for: system,
            targetLoudness: targetLoudness,
            maxBoost: limits.maxBoost,
            maxAttenuation: limits.maxAttenuation
        )

        if microphone?.clippingDetected == true {
            microphoneGain = min(microphoneGain, 0)
        }
        if system?.clippingDetected == true {
            systemGain = min(systemGain, 0)
        }

        let safePeakAdjustment = safePeakAdjustmentDB(
            microphone: microphoneUsable ? microphone : nil,
            microphoneGain: microphoneGain,
            system: systemUsable ? system : nil,
            systemGain: systemGain
        )
        if safePeakAdjustment < 0 {
            if microphoneUsable {
                microphoneGain += safePeakAdjustment
            }
            if systemUsable {
                systemGain += safePeakAdjustment
            }
        }

        let status: BalancedMixStatus = microphoneUsable && systemUsable ? .done : .partial
        let usedSourceKinds = [
            microphoneUsable ? "microphone" : nil,
            systemUsable ? "system" : nil
        ].compactMap { $0 }

        return AudioBalancePlan(
            microphoneGainDB: roundedGain(microphoneUsable ? microphoneGain : 0),
            systemGainDB: roundedGain(systemUsable ? systemGain : 0),
            limiterCeilingDBFS: limiterCeilingDBFS,
            limiterRequired: true,
            status: status,
            usedSourceKinds: usedSourceKinds,
            warnings: unique(warnings)
        )
    }

    private func isUsable(_ analysis: AudioLevelAnalysis?) -> Bool {
        guard let analysis else {
            return false
        }

        return analysis.exists
            && analysis.fileSizeBytes > 0
            && analysis.hasUsableSignal
            && analysis.silenceRatio < 0.98
    }

    private func warnings(
        for microphone: AudioLevelAnalysis?,
        system: AudioLevelAnalysis?
    ) -> [AudioLevelingWarning] {
        var warnings: [AudioLevelingWarning] = []

        if let microphone, (!microphone.hasUsableSignal || microphone.silenceRatio >= 0.95) {
            warnings.append(.microphoneSeemsSilent)
        }
        if let system, (!system.hasUsableSignal || system.silenceRatio >= 0.95) {
            warnings.append(.systemSeemsSilent)
        }
        if microphone?.clippingDetected == true {
            warnings.append(.microphoneClippingDetected)
        }
        if system?.clippingDetected == true {
            warnings.append(.systemClippingDetected)
        }

        return warnings
    }

    private func limits(for mode: AudioLevelingMode) -> (maxBoost: Double, maxAttenuation: Double) {
        switch mode {
        case .balanced, .voiceBoost:
            return (maxGainBoostDB, maxAttenuationDB)
        case .conservative:
            return (min(maxGainBoostDB, 6), min(maxAttenuationDB, 6))
        }
    }

    private func targetLoudness(for usable: [AudioLevelAnalysis]) -> Double {
        guard usable.count > 1 else {
            return -24
        }

        let average = usable.map(\.approximateLoudnessDB).reduce(0, +) / Double(usable.count)
        return min(-22, max(-32, average))
    }

    private func gain(
        for analysis: AudioLevelAnalysis?,
        targetLoudness: Double,
        maxBoost: Double,
        maxAttenuation: Double
    ) -> Double {
        guard let analysis,
              isUsable(analysis),
              analysis.approximateLoudnessDB.isFinite
        else {
            return 0
        }

        let desired = targetLoudness - analysis.approximateLoudnessDB
        return min(maxBoost, max(-maxAttenuation, desired))
    }

    private func safePeakAdjustmentDB(
        microphone: AudioLevelAnalysis?,
        microphoneGain: Double,
        system: AudioLevelAnalysis?,
        systemGain: Double
    ) -> Double {
        let peaks = [
            microphone.map { $0.peakDBFS + microphoneGain },
            system.map { $0.peakDBFS + systemGain }
        ].compactMap { $0 }.filter(\.isFinite)

        guard !peaks.isEmpty else {
            return 0
        }

        let mixedPeakLinear = peaks
            .map { pow(10, $0 / 20) }
            .reduce(0, +)
        guard mixedPeakLinear > 0 else {
            return 0
        }

        let estimatedMixedPeakDBFS = 20 * log10(mixedPeakLinear)
        guard estimatedMixedPeakDBFS > limiterCeilingDBFS else {
            return 0
        }

        return limiterCeilingDBFS - estimatedMixedPeakDBFS
    }

    private func roundedGain(_ value: Double) -> Double {
        guard value.isFinite else {
            return 0
        }

        return (value * 10).rounded() / 10
    }

    private func unique(_ warnings: [AudioLevelingWarning]) -> [AudioLevelingWarning] {
        var seen = Set<AudioLevelingWarning>()
        return warnings.filter { seen.insert($0).inserted }
    }
}

public struct AudioBalancedMixerResult: Equatable, Sendable {
    public let track: AudioTrackMetadata
    public let duration: TimeInterval
    public let fileSizeBytes: Int64
    public let usedSourceKinds: [String]
}

public final class AudioBalancedMixer: @unchecked Sendable {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 2

    public init() {}

    public func createBalancedMix(
        micURL: URL,
        systemURL: URL,
        outputURL: URL,
        plan: AudioBalancePlan,
        qualityPreset: AudioQualityPreset = .standard
    ) async throws -> AudioBalancedMixerResult {
        let candidates = [
            BalancedSourceTrack(kind: "microphone", url: micURL, gainDB: plan.microphoneGainDB),
            BalancedSourceTrack(kind: "system", url: systemURL, gainDB: plan.systemGainDB)
        ].filter { plan.usedSourceKinds.contains($0.kind) && Self.isUsableFile($0.url) }

        guard !candidates.isEmpty else {
            throw RecordingControllerError.mixedAudioNoSourceTracks
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.removeItemIfExists(at: outputURL)

        let mix = try await makeComposition(from: candidates)
        guard !mix.audioTracks.isEmpty else {
            throw RecordingControllerError.mixedAudioNoSourceTracks
        }

        try await write(
            composition: mix.composition,
            audioTracks: mix.audioTracks,
            audioMix: mix.audioMix,
            outputURL: outputURL,
            qualityPreset: qualityPreset
        )

        let fileSize = try Self.fileSize(at: outputURL)
        guard fileSize > 0 else {
            throw RecordingControllerError.mixedAudioWriteFailed("Empty file at \(outputURL.path(percentEncoded: false))")
        }

        let duration = max(0, CMTimeGetSeconds(mix.composition.duration))
        let track = AudioTrackMetadata(
            kind: "mixed_balanced",
            relativePath: AudioLevelTrackKind.mixedBalanced.relativePath,
            codec: "aac",
            container: "m4a",
            durationSec: duration,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            bitrate: qualityPreset.mixedPreviewBitrate,
            fileSizeBytes: fileSize,
            status: "completed",
            signal: AudioSignalAnalyzer.analyze(url: outputURL)
        )

        AppLogger.file(.info, category: "recording", "balanced mix created output=\(outputURL.path(percentEncoded: false)) size=\(fileSize) mic_gain_db=\(plan.microphoneGainDB) system_gain_db=\(plan.systemGainDB)")

        return AudioBalancedMixerResult(
            track: track,
            duration: duration,
            fileSizeBytes: fileSize,
            usedSourceKinds: mix.usedSourceKinds
        )
    }

    private func makeComposition(from candidates: [BalancedSourceTrack]) async throws -> BalancedAudioMixComposition {
        let composition = AVMutableComposition()
        let audioMix = AVMutableAudioMix()
        var audioTracks: [AVAssetTrack] = []
        var inputParameters: [AVAudioMixInputParameters] = []
        var usedSourceKinds: [String] = []

        for candidate in candidates {
            let asset = AVURLAsset(url: candidate.url)
            do {
                let duration = try await asset.load(.duration)
                let sourceTracks = try await asset.loadTracks(withMediaType: .audio)

                guard let sourceTrack = sourceTracks.first,
                      duration.isNumeric,
                      duration > .zero
                else {
                    AppLogger.file(.warning, category: "recording", "skipping unusable balanced source kind=\(candidate.kind) path=\(candidate.url.path(percentEncoded: false))")
                    continue
                }

                guard let compositionTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                ) else {
                    throw RecordingControllerError.mixedAudioSetupFailed("AVMutableComposition cannot add audio track")
                }

                try compositionTrack.insertTimeRange(
                    CMTimeRange(start: .zero, duration: duration),
                    of: sourceTrack,
                    at: .zero
                )

                let parameters = AVMutableAudioMixInputParameters(track: compositionTrack)
                parameters.setVolume(Self.linearGain(fromDB: candidate.gainDB), at: .zero)
                inputParameters.append(parameters)
                audioTracks.append(compositionTrack)
                usedSourceKinds.append(candidate.kind)
            } catch let error as RecordingControllerError {
                throw error
            } catch {
                AppLogger.file(.warning, category: "recording", "skipping unreadable balanced source kind=\(candidate.kind) path=\(candidate.url.path(percentEncoded: false)) error=\(String(describing: error))")
            }
        }

        audioMix.inputParameters = inputParameters
        return BalancedAudioMixComposition(
            composition: composition,
            audioTracks: audioTracks,
            audioMix: audioMix,
            usedSourceKinds: usedSourceKinds
        )
    }

    private func write(
        composition: AVAsset,
        audioTracks: [AVAssetTrack],
        audioMix: AVAudioMix,
        outputURL: URL,
        qualityPreset: AudioQualityPreset
    ) async throws {
        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: composition)
        } catch {
            throw RecordingControllerError.mixedAudioSetupFailed(String(describing: error))
        }

        let readerOutput = AVAssetReaderAudioMixOutput(
            audioTracks: audioTracks,
            audioSettings: Self.readerAudioSettings
        )
        readerOutput.audioMix = audioMix

        guard reader.canAdd(readerOutput) else {
            throw RecordingControllerError.mixedAudioSetupFailed("AVAssetReader cannot add balanced audio mix output")
        }
        reader.add(readerOutput)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw RecordingControllerError.mixedAudioSetupFailed(String(describing: error))
        }

        let writerInput = AVAssetWriterInput(
            mediaType: .audio,
            outputSettings: Self.writerAudioSettings(for: qualityPreset)
        )
        writerInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(writerInput) else {
            throw RecordingControllerError.mixedAudioSetupFailed("AVAssetWriter cannot add balanced AAC audio input")
        }
        writer.add(writerInput)

        guard writer.startWriting() else {
            throw RecordingControllerError.mixedAudioWriteFailed(writer.error.map(String.init(describing:)) ?? "AVAssetWriter failed to start")
        }

        guard reader.startReading() else {
            writer.cancelWriting()
            throw RecordingControllerError.mixedAudioSetupFailed(reader.error.map(String.init(describing:)) ?? "AVAssetReader failed to start")
        }

        writer.startSession(atSourceTime: .zero)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let queue = DispatchQueue(label: "com.torbit.recorder.balanced-audio-writer")
            let completion = BalancedMixContinuationCompletion(continuation: continuation)

            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData && !completion.isFinished {
                    guard let sampleBuffer = readerOutput.copyNextSampleBuffer() else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if let readerError = reader.error {
                                completion.finish(.failure(RecordingControllerError.mixedAudioWriteFailed(String(describing: readerError))))
                            } else if reader.status == .failed || reader.status == .cancelled {
                                completion.finish(.failure(RecordingControllerError.mixedAudioWriteFailed("AVAssetReader status: \(reader.status.rawValue)")))
                            } else if let writerError = writer.error {
                                completion.finish(.failure(RecordingControllerError.mixedAudioWriteFailed(String(describing: writerError))))
                            } else if writer.status == .failed || writer.status == .cancelled {
                                completion.finish(.failure(RecordingControllerError.mixedAudioWriteFailed("AVAssetWriter status: \(writer.status.rawValue)")))
                            } else {
                                completion.finish(.success(()))
                            }
                        }
                        return
                    }

                    if !writerInput.append(sampleBuffer) {
                        reader.cancelReading()
                        writerInput.markAsFinished()
                        writer.cancelWriting()
                        completion.finish(.failure(RecordingControllerError.mixedAudioWriteFailed(writer.error.map(String.init(describing:)) ?? "AVAssetWriter append failed")))
                        return
                    }
                }
            }
        }
    }

    private static var readerAudioSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsNonInterleaved: false
        ]
    }

    private static func writerAudioSettings(for preset: AudioQualityPreset) -> [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: preset.mixedPreviewBitrate,
            AVEncoderBitRateStrategyKey: AVAudioBitRateStrategy_Constant
        ]
    }

    private static func isUsableFile(_ url: URL) -> Bool {
        (try? fileSize(at: url)) ?? 0 > 0
    }

    private static func fileSize(at url: URL) throws -> Int64 {
        let path = url.path(percentEncoded: false)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return (attributes[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func linearGain(fromDB gainDB: Double) -> Float {
        guard gainDB.isFinite else {
            return 1
        }

        return Float(pow(10, gainDB / 20))
    }
}

public struct AudioLevelingAnalysisDocument: Codable, Equatable, Sendable {
    public var schemaVersion: Int
    public var recordingID: String
    public var createdAt: String
    public var mode: AudioLevelingMode
    public var microphone: AudioLevelAnalysis
    public var system: AudioLevelAnalysis
    public var plan: AudioBalancePlan
    public var output: AudioLevelingOutputAnalysis?

    public init(
        recordingID: String,
        createdAt: Date = Date(),
        mode: AudioLevelingMode,
        microphone: AudioLevelAnalysis,
        system: AudioLevelAnalysis,
        plan: AudioBalancePlan,
        output: AudioLevelingOutputAnalysis?
    ) {
        self.schemaVersion = 1
        self.recordingID = recordingID
        self.createdAt = Self.formatISO8601(createdAt)
        self.mode = mode
        self.microphone = microphone
        self.system = system
        self.plan = plan
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion = "schema_version"
        case recordingID = "recording_id"
        case createdAt = "created_at"
        case mode
        case microphone
        case system
        case plan
        case output
    }

    private static func formatISO8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

public struct AudioLevelingOutputAnalysis: Codable, Equatable, Sendable {
    public var relativePath: String
    public var fileSizeBytes: Int64
    public var durationSec: Double
    public var integrityOK: Bool

    public init(
        relativePath: String,
        fileSizeBytes: Int64,
        durationSec: Double,
        integrityOK: Bool
    ) {
        self.relativePath = relativePath
        self.fileSizeBytes = fileSizeBytes
        self.durationSec = durationSec
        self.integrityOK = integrityOK
    }

    enum CodingKeys: String, CodingKey {
        case relativePath = "relative_path"
        case fileSizeBytes = "file_size_bytes"
        case durationSec = "duration_sec"
        case integrityOK = "integrity_ok"
    }
}

public enum AudioLevelingAnalysisCodec {
    public static func write(_ document: AudioLevelingAnalysisDocument, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(document)
        try data.write(to: url, options: [.atomic])
    }
}

private struct BalancedSourceTrack {
    let kind: String
    let url: URL
    let gainDB: Double
}

private struct BalancedAudioMixComposition {
    let composition: AVMutableComposition
    let audioTracks: [AVAssetTrack]
    let audioMix: AVAudioMix
    let usedSourceKinds: [String]
}

private final class BalancedMixContinuationCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var didFinish = false
    private let continuation: CheckedContinuation<Void, Error>

    var isFinished: Bool {
        lock.withLock {
            didFinish
        }
    }

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func finish(_ result: Result<Void, Error>) {
        let shouldResume = lock.withLock {
            if didFinish {
                return false
            }
            didFinish = true
            return true
        }

        guard shouldResume else {
            return
        }

        switch result {
        case .success:
            continuation.resume()
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }
}

private extension FileManager {
    func removeItemIfExists(at url: URL) throws {
        let path = url.path(percentEncoded: false)
        if fileExists(atPath: path) {
            try removeItem(at: url)
        }
    }
}
