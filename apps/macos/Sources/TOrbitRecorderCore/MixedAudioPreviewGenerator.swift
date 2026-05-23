@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

public struct MixedAudioPreviewResult: Equatable, Sendable {
    public let track: AudioTrackMetadata
    public let duration: TimeInterval
    public let fileSizeBytes: Int64
    public let usedSourceKinds: [String]
}

public final class MixedAudioPreviewGenerator: @unchecked Sendable {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 2
    public static let bitrate: Int = 96_000

    public init() {}

    public func createPreview(
        micURL: URL,
        systemURL: URL,
        outputURL: URL
    ) async throws -> MixedAudioPreviewResult {
        let candidates = [
            SourceTrack(kind: "microphone", url: micURL),
            SourceTrack(kind: "system", url: systemURL)
        ].filter { Self.isUsableFile($0.url) }

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
            outputURL: outputURL
        )

        let fileSize = try Self.fileSize(at: outputURL)
        guard fileSize > 0 else {
            throw RecordingControllerError.mixedAudioWriteFailed("Empty file at \(outputURL.path(percentEncoded: false))")
        }

        let duration = max(0, CMTimeGetSeconds(mix.composition.duration))
        let track = AudioTrackMetadata(
            kind: "mixed",
            relativePath: "export/mixed.m4a",
            codec: "aac",
            container: "m4a",
            durationSec: duration,
            sampleRate: Self.sampleRate,
            channels: Self.channels,
            bitrate: Self.bitrate,
            fileSizeBytes: fileSize,
            status: "completed"
        )

        AppLogger.recording.info(
            "Mixed audio preview created: \(outputURL.path(percentEncoded: false), privacy: .public), size=\(fileSize, privacy: .public)"
        )

        return MixedAudioPreviewResult(
            track: track,
            duration: duration,
            fileSizeBytes: fileSize,
            usedSourceKinds: mix.usedSourceKinds
        )
    }

    private func makeComposition(from candidates: [SourceTrack]) async throws -> AudioMixComposition {
        let composition = AVMutableComposition()
        let audioMix = AVMutableAudioMix()
        let sourceVolume: Float = candidates.count > 1 ? 0.75 : 1.0
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
                    AppLogger.recording.error("Skipping unusable source track for mixed preview: \(candidate.url.path(percentEncoded: false), privacy: .public)")
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
                parameters.setVolume(sourceVolume, at: .zero)
                inputParameters.append(parameters)
                audioTracks.append(compositionTrack)
                usedSourceKinds.append(candidate.kind)
            } catch let error as RecordingControllerError {
                throw error
            } catch {
                AppLogger.recording.error(
                    "Skipping unreadable source track for mixed preview: \(candidate.url.path(percentEncoded: false), privacy: .public), error=\(String(describing: error), privacy: .public)"
                )
            }
        }

        audioMix.inputParameters = inputParameters

        return AudioMixComposition(
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
        outputURL: URL
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
            throw RecordingControllerError.mixedAudioSetupFailed("AVAssetReader cannot add audio mix output")
        }
        reader.add(readerOutput)

        let writer: AVAssetWriter
        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        } catch {
            throw RecordingControllerError.mixedAudioSetupFailed(String(describing: error))
        }

        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.writerAudioSettings)
        writerInput.expectsMediaDataInRealTime = false

        guard writer.canAdd(writerInput) else {
            throw RecordingControllerError.mixedAudioSetupFailed("AVAssetWriter cannot add AAC audio input")
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
            let queue = DispatchQueue(label: "com.torbit.recorder.mixed-audio-writer")
            let completion = ContinuationCompletion(continuation: continuation)

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

    private static var writerAudioSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate,
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
}

private struct SourceTrack {
    let kind: String
    let url: URL
}

private struct AudioMixComposition {
    let composition: AVMutableComposition
    let audioTracks: [AVAssetTrack]
    let audioMix: AVAudioMix
    let usedSourceKinds: [String]
}

private final class ContinuationCompletion: @unchecked Sendable {
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
