@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation
@preconcurrency import ScreenCaptureKit

public struct SystemAudioRecordingResult: Equatable, Sendable {
    public let duration: TimeInterval
    public let sampleCount: Int
    public let fileSize: Int64
}

public final class ScreenCaptureKitSystemAudioRecorder: NSObject, @unchecked Sendable, SCStreamOutput, SCStreamDelegate {
    public static let sampleRate: Double = 48_000
    public static let channels: Int = 2
    public static let bitrate: Int = 128_000

    public static var assetWriterAudioSettings: [String: Any] {
        [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitrate
        ]
    }

    public static func streamConfiguration() -> SCStreamConfiguration {
        let configuration = SCStreamConfiguration()
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.queueDepth = 1
        configuration.showsCursor = false
        configuration.capturesAudio = true
        configuration.captureMicrophone = false
        configuration.sampleRate = Int(Self.sampleRate)
        configuration.channelCount = Self.channels
        configuration.excludesCurrentProcessAudio = false
        return configuration
    }

    private let outputQueue = DispatchQueue(label: "com.torbit.recorder.system-audio")

    private var stream: SCStream?
    private var writer: AVAssetWriter?
    private var writerInput: AVAssetWriterInput?
    private var outputURL: URL?
    private var didStartWriting = false
    private var sampleCount = 0
    private var firstSampleTime: CMTime?
    private var lastSampleTime: CMTime?
    private var streamError: Error?

    public func start(outputURL: URL) async throws {
        try FileManager.default.removeItemIfExists(at: outputURL)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.current
        } catch {
            AppLogger.recording.error("ScreenCaptureKit shareable content unavailable: \(String(describing: error), privacy: .public)")
            throw Self.mapScreenCaptureKitError(error)
        }

        guard let display = content.displays.first else {
            throw RecordingControllerError.noShareableDisplay
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = Self.streamConfiguration()
        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .m4a)
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.assetWriterAudioSettings)
        writerInput.expectsMediaDataInRealTime = true

        guard writer.canAdd(writerInput) else {
            throw RecordingControllerError.systemAudioSetupFailed("AVAssetWriter cannot add system audio input")
        }

        writer.add(writerInput)

        self.stream = stream
        self.writer = writer
        self.writerInput = writerInput
        self.outputURL = outputURL
        self.didStartWriting = false
        self.sampleCount = 0
        self.firstSampleTime = nil
        self.lastSampleTime = nil
        self.streamError = nil

        do {
            try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: outputQueue)
            try await stream.startCapture()
        } catch {
            resetState()
            AppLogger.recording.error("Failed to start ScreenCaptureKit system audio: \(String(describing: error), privacy: .public)")
            throw Self.mapScreenCaptureKitError(error)
        }

        AppLogger.recording.info("System audio capture started: \(outputURL.path(percentEncoded: false), privacy: .public)")
    }

    public func stop() async throws -> SystemAudioRecordingResult {
        guard let stream, let writer, let writerInput, let outputURL else {
            throw RecordingControllerError.notRecording
        }

        do {
            try await stream.stopCapture()
            try? stream.removeStreamOutput(self, type: .audio)
        } catch {
            resetState()
            throw RecordingControllerError.systemAudioSetupFailed(String(describing: error))
        }

        let snapshot = outputQueue.sync { () -> (Int, CMTime?, CMTime?, Error?) in
            writerInput.markAsFinished()
            return (sampleCount, firstSampleTime, lastSampleTime, streamError)
        }

        if let error = snapshot.3 {
            resetState()
            throw RecordingControllerError.systemAudioWriteFailed(String(describing: error))
        }

        try await finishWriting(writer)

        let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path(percentEncoded: false))
        let fileSize = (attributes[.size] as? NSNumber)?.int64Value ?? 0

        guard snapshot.0 > 0 else {
            resetState()
            throw RecordingControllerError.systemAudioNoSamples
        }

        guard fileSize > 0 else {
            resetState()
            throw RecordingControllerError.systemAudioWriteFailed("Empty file at \(outputURL.path(percentEncoded: false))")
        }

        let duration = Self.duration(first: snapshot.1, last: snapshot.2)
        resetState()
        AppLogger.recording.info("System audio capture stopped after \(duration, privacy: .public) seconds")

        return SystemAudioRecordingResult(
            duration: duration,
            sampleCount: snapshot.0,
            fileSize: fileSize
        )
    }

    nonisolated public func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else {
            return
        }

        append(sampleBuffer)
    }

    nonisolated public func stream(_ stream: SCStream, didStopWithError error: Error) {
        AppLogger.recording.error("ScreenCaptureKit stream stopped with error: \(String(describing: error), privacy: .public)")
        outputQueue.async { [weak self] in
            self?.streamError = error
        }
    }

    private func append(_ sampleBuffer: CMSampleBuffer) {
        guard let writer, let writerInput else {
            return
        }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        if !didStartWriting {
            guard writer.startWriting() else {
                streamError = writer.error
                return
            }

            writer.startSession(atSourceTime: presentationTime)
            didStartWriting = true
            firstSampleTime = presentationTime
        }

        guard writerInput.isReadyForMoreMediaData else {
            return
        }

        if writerInput.append(sampleBuffer) {
            sampleCount += 1
            lastSampleTime = presentationTime
        } else {
            streamError = writer.error
        }
    }

    private func finishWriting(_ writer: AVAssetWriter) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            writer.finishWriting {
                if writer.status == .failed || writer.status == .cancelled {
                    continuation.resume(
                        throwing: RecordingControllerError.systemAudioWriteFailed(
                            writer.error.map(String.init(describing:)) ?? "AVAssetWriter failed"
                        )
                    )
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func resetState() {
        stream = nil
        writer = nil
        writerInput = nil
        outputURL = nil
        didStartWriting = false
        sampleCount = 0
        firstSampleTime = nil
        lastSampleTime = nil
        streamError = nil
    }

    private static func duration(first: CMTime?, last: CMTime?) -> TimeInterval {
        guard let first, let last else {
            return 0
        }

        return max(0, CMTimeGetSeconds(CMTimeSubtract(last, first)))
    }

    private static func mapScreenCaptureKitError(_ error: Error) -> RecordingControllerError {
        let nsError = error as NSError
        let message = "\(nsError.localizedDescription) (domain: \(nsError.domain), code: \(nsError.code))"

        guard nsError.domain == SCStreamErrorDomain,
              let code = SCStreamError.Code(rawValue: nsError.code)
        else {
            return .systemAudioSetupFailed(message)
        }

        switch code {
        case .userDeclined, .missingEntitlements:
            return .systemAudioPermissionDenied(message)
        case .noDisplayList, .noCaptureSource:
            return .noShareableDisplay
        default:
            return .systemAudioSetupFailed(message)
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
