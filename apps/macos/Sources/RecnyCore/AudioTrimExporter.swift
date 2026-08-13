@preconcurrency import AVFoundation
@preconcurrency import CoreMedia
import Foundation

public enum AudioTrimError: Error, Equatable, Sendable, CustomStringConvertible {
    case sourceMissing
    case invalidRange
    case unreadableDuration
    case exportUnavailable
    case exportFailed(String)
    case emptyOutput

    public var description: String {
        switch self {
        case .sourceMissing:
            return "No source audio file is available for trimming"
        case .invalidRange:
            return "Trim range is invalid"
        case .unreadableDuration:
            return "Could not read audio duration"
        case .exportUnavailable:
            return "Audio trim export is unavailable for this file"
        case .exportFailed(let message):
            return "Audio trim export failed: \(message)"
        case .emptyOutput:
            return "Trimmed audio output is empty"
        }
    }
}

public struct AudioTrimResult: Equatable, Sendable {
    public let sourceURL: URL
    public let outputURL: URL
    public let durationSec: TimeInterval
    public let fileSizeBytes: Int64

    public init(
        sourceURL: URL,
        outputURL: URL,
        durationSec: TimeInterval,
        fileSizeBytes: Int64
    ) {
        self.sourceURL = sourceURL
        self.outputURL = outputURL
        self.durationSec = durationSec
        self.fileSizeBytes = fileSizeBytes
    }
}

public final class AudioTrimExporter: @unchecked Sendable {
    private static let minimumClipDuration: TimeInterval = 0.05

    public init() {}

    public static func audioDuration(of url: URL) async throws -> TimeInterval {
        guard nonEmptyFileSize(at: url) != nil else {
            throw AudioTrimError.sourceMissing
        }

        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        guard duration.isNumeric else {
            throw AudioTrimError.unreadableDuration
        }

        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw AudioTrimError.unreadableDuration
        }

        return seconds
    }

    public func exportClip(
        sourceURL: URL,
        outputURL: URL,
        startSeconds: TimeInterval,
        endSeconds: TimeInterval
    ) async throws -> AudioTrimResult {
        guard endSeconds > startSeconds else {
            throw AudioTrimError.invalidRange
        }

        let sourceDuration = try await Self.audioDuration(of: sourceURL)
        let start = max(0, startSeconds)
        let end = min(sourceDuration, endSeconds)
        guard start < end,
              end - start >= Self.minimumClipDuration
        else {
            throw AudioTrimError.invalidRange
        }

        let asset = AVURLAsset(url: sourceURL)
        guard let exportSession = AVAssetExportSession(
            asset: asset,
            presetName: AVAssetExportPresetAppleM4A
        ) else {
            throw AudioTrimError.exportUnavailable
        }

        try FileManager.default.createDirectory(
            at: outputURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.removeItemIfExists(at: outputURL)

        exportSession.timeRange = CMTimeRange(
            start: CMTime(seconds: start, preferredTimescale: 600),
            duration: CMTime(seconds: end - start, preferredTimescale: 600)
        )

        try await export(exportSession, outputURL: outputURL)

        guard let fileSize = Self.nonEmptyFileSize(at: outputURL) else {
            throw AudioTrimError.emptyOutput
        }

        AppLogger.file(
            .info,
            category: "library",
            "audio clip exported source=\(sourceURL.path(percentEncoded: false)) output=\(outputURL.path(percentEncoded: false)) start=\(String(format: "%.2f", start)) end=\(String(format: "%.2f", end))"
        )

        return AudioTrimResult(
            sourceURL: sourceURL,
            outputURL: outputURL,
            durationSec: end - start,
            fileSizeBytes: fileSize
        )
    }

    private func export(_ exportSession: AVAssetExportSession, outputURL: URL) async throws {
        do {
            try await exportSession.export(to: outputURL, as: .m4a)
        } catch {
            throw AudioTrimError.exportFailed(String(describing: error))
        }
    }

    private static func nonEmptyFileSize(at url: URL) -> Int64? {
        guard let size = try? FileManager.default
            .attributesOfItem(atPath: url.path(percentEncoded: false))[.size] as? NSNumber,
              size.int64Value > 0
        else {
            return nil
        }
        return size.int64Value
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
