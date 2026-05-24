import Foundation

public enum AudioReprocessOverwritePolicy: Equatable, Sendable {
    case skipExisting
    case overwriteExisting
}

public enum AudioReprocessStatus: String, Equatable, Sendable {
    case processed
    case skippedExisting = "skipped_existing"
    case failed
}

public struct AudioReprocessResult: Equatable, Identifiable, Sendable {
    public let id: String
    public let recordingID: String
    public let title: String
    public let status: AudioReprocessStatus
    public let message: String
    public let balancedAudioURL: URL
    public let analysisURL: URL

    public init(
        recordingID: String,
        title: String,
        status: AudioReprocessStatus,
        message: String,
        balancedAudioURL: URL,
        analysisURL: URL
    ) {
        self.id = recordingID
        self.recordingID = recordingID
        self.title = title
        self.status = status
        self.message = message
        self.balancedAudioURL = balancedAudioURL
        self.analysisURL = analysisURL
    }
}

public struct AudioReprocessBatchSummary: Equatable, Sendable {
    public let results: [AudioReprocessResult]

    public init(results: [AudioReprocessResult]) {
        self.results = results
    }

    public var processedCount: Int {
        results.filter { $0.status == .processed }.count
    }

    public var skippedCount: Int {
        results.filter { $0.status == .skippedExisting }.count
    }

    public var failedCount: Int {
        results.filter { $0.status == .failed }.count
    }

    public var displayText: String {
        "Processed \(processedCount), skipped \(skippedCount), failed \(failedCount)"
    }
}

public struct AudioReprocessProgress: Equatable, Sendable {
    public let completed: Int
    public let total: Int
    public let currentTitle: String

    public init(completed: Int, total: Int, currentTitle: String) {
        self.completed = completed
        self.total = total
        self.currentTitle = currentTitle
    }

    public var displayText: String {
        guard total > 0 else {
            return "No recordings to reprocess"
        }

        return "Reprocessing \(min(completed + 1, total)) of \(total): \(currentTitle)"
    }
}

@MainActor
public final class AudioLevelingReprocessor {
    private let store: FileSystemRecordingStore
    private let analyzer: AudioLevelAnalyzer
    private let planner: AudioBalancePlanner
    private let mixer: AudioBalancedMixer
    private let qualityPreset: AudioQualityPreset
    private let mode: AudioLevelingMode

    public init(
        store: FileSystemRecordingStore,
        analyzer: AudioLevelAnalyzer = AudioLevelAnalyzer(),
        planner: AudioBalancePlanner = AudioBalancePlanner(),
        mixer: AudioBalancedMixer = AudioBalancedMixer(),
        qualityPreset: AudioQualityPreset = .standard,
        mode: AudioLevelingMode = .balanced
    ) {
        self.store = store
        self.analyzer = analyzer
        self.planner = planner
        self.mixer = mixer
        self.qualityPreset = qualityPreset
        self.mode = mode.isImplemented ? mode : .balanced
    }

    public func reprocess(
        recording: RecordingSummary,
        overwritePolicy: AudioReprocessOverwritePolicy
    ) async throws -> AudioReprocessResult {
        let sessionFolderURL = recording.sessionFolderURL
        let micURL = sessionFolderURL.appendingPathComponent(AudioLevelTrackKind.microphone.relativePath)
        let systemURL = sessionFolderURL.appendingPathComponent(AudioLevelTrackKind.system.relativePath)
        let balancedURL = sessionFolderURL.appendingPathComponent(AudioLevelTrackKind.mixedBalanced.relativePath)
        let analysisRelativePath = "analysis/audio_analysis.json"
        let analysisURL = sessionFolderURL.appendingPathComponent(analysisRelativePath)

        if overwritePolicy == .skipExisting,
           RecordingPlaybackResolver.nonEmptyFileSize(at: balancedURL) != nil {
            AppLogger.file(.info, category: "recording", "audio reprocess skipped existing balanced recording_id=\(recording.id)")
            return AudioReprocessResult(
                recordingID: recording.id,
                title: recording.title,
                status: .skippedExisting,
                message: "Balanced audio already exists",
                balancedAudioURL: balancedURL,
                analysisURL: analysisURL
            )
        }

        var metadata = try store.readMetadata(at: recording.metadataURL)
        let microphoneAnalysis = analyzer.analyzeIfPresent(url: micURL, kind: .microphone)
        let systemAnalysis = analyzer.analyzeIfPresent(url: systemURL, kind: .system)
        let plan = planner.plan(
            microphone: microphoneAnalysis,
            system: systemAnalysis,
            mode: mode
        )

        metadata.audioTracks = upsertingSourceTracks(
            in: metadata.audioTracks,
            microphone: microphoneAnalysis,
            system: systemAnalysis
        )

        guard plan.status != .failed else {
            let processing = AudioProcessingMetadata(
                balancedMixStatus: .failed,
                balancedMixPath: AudioLevelTrackKind.mixedBalanced.relativePath,
                analysisPath: analysisRelativePath,
                microphoneGainDB: plan.microphoneGainDB,
                systemGainDB: plan.systemGainDB,
                warnings: plan.warnings.map(\.message)
            )
            metadata.status = .failed
            metadata.audioTracks = upserting(
                AudioTrackMetadata(
                    kind: "mixed_balanced",
                    relativePath: AudioLevelTrackKind.mixedBalanced.relativePath,
                    codec: "aac",
                    container: "m4a",
                    sampleRate: AudioBalancedMixer.sampleRate,
                    channels: AudioBalancedMixer.channels,
                    bitrate: qualityPreset.mixedPreviewBitrate,
                    status: "failed",
                    error: "No usable source tracks for balanced mix"
                ),
                into: metadata.audioTracks
            )
            metadata.audio = makeAudioMetadata(
                processing: processing,
                audioTracks: metadata.audioTracks,
                microphoneAnalysis: microphoneAnalysis,
                systemAnalysis: systemAnalysis
            )
            try writeAnalysis(
                recordingID: metadata.id,
                microphone: microphoneAnalysis,
                system: systemAnalysis,
                plan: plan,
                output: nil,
                to: analysisURL
            )
            try store.writeMetadata(
                metadata,
                metadataURL: recording.metadataURL,
                sessionFolderURL: sessionFolderURL
            )
            AppLogger.file(.warning, category: "recording", "audio reprocess failed no usable source tracks recording_id=\(recording.id)")
            return AudioReprocessResult(
                recordingID: recording.id,
                title: recording.title,
                status: .failed,
                message: "No usable source audio files",
                balancedAudioURL: balancedURL,
                analysisURL: analysisURL
            )
        }

        do {
            let result = try await mixer.createBalancedMix(
                micURL: micURL,
                systemURL: systemURL,
                outputURL: balancedURL,
                plan: plan,
                qualityPreset: qualityPreset
            )
            metadata.audioTracks = upserting(result.track, into: metadata.audioTracks)

            let processing = AudioProcessingMetadata(
                balancedMixStatus: plan.status,
                balancedMixPath: AudioLevelTrackKind.mixedBalanced.relativePath,
                analysisPath: analysisRelativePath,
                microphoneGainDB: plan.microphoneGainDB,
                systemGainDB: plan.systemGainDB,
                warnings: plan.warnings.map(\.message)
            )
            metadata.audio = makeAudioMetadata(
                processing: processing,
                audioTracks: metadata.audioTracks,
                microphoneAnalysis: microphoneAnalysis,
                systemAnalysis: systemAnalysis
            )
            try writeAnalysis(
                recordingID: metadata.id,
                microphone: microphoneAnalysis,
                system: systemAnalysis,
                plan: plan,
                output: AudioLevelingOutputAnalysis(
                    relativePath: AudioLevelTrackKind.mixedBalanced.relativePath,
                    fileSizeBytes: result.fileSizeBytes,
                    durationSec: result.duration,
                    integrityOK: result.fileSizeBytes > 0
                ),
                to: analysisURL
            )
            try store.writeMetadata(
                metadata,
                metadataURL: recording.metadataURL,
                sessionFolderURL: sessionFolderURL
            )
            AppLogger.file(.info, category: "recording", "audio reprocess completed recording_id=\(recording.id) balanced=\(balancedURL.path(percentEncoded: false))")
            return AudioReprocessResult(
                recordingID: recording.id,
                title: recording.title,
                status: .processed,
                message: "Balanced audio created",
                balancedAudioURL: balancedURL,
                analysisURL: analysisURL
            )
        } catch {
            let processing = AudioProcessingMetadata(
                balancedMixStatus: .failed,
                balancedMixPath: AudioLevelTrackKind.mixedBalanced.relativePath,
                analysisPath: analysisRelativePath,
                microphoneGainDB: plan.microphoneGainDB,
                systemGainDB: plan.systemGainDB,
                warnings: (plan.warnings + [.balancedMixFailed]).map(\.message)
            )
            metadata.audioTracks = upserting(
                AudioTrackMetadata(
                    kind: "mixed_balanced",
                    relativePath: AudioLevelTrackKind.mixedBalanced.relativePath,
                    codec: "aac",
                    container: "m4a",
                    sampleRate: AudioBalancedMixer.sampleRate,
                    channels: AudioBalancedMixer.channels,
                    bitrate: qualityPreset.mixedPreviewBitrate,
                    status: "failed",
                    error: String(describing: error)
                ),
                into: metadata.audioTracks
            )
            metadata.audio = makeAudioMetadata(
                processing: processing,
                audioTracks: metadata.audioTracks,
                microphoneAnalysis: microphoneAnalysis,
                systemAnalysis: systemAnalysis
            )
            try? writeAnalysis(
                recordingID: metadata.id,
                microphone: microphoneAnalysis,
                system: systemAnalysis,
                plan: plan,
                output: nil,
                to: analysisURL
            )
            try store.writeMetadata(
                metadata,
                metadataURL: recording.metadataURL,
                sessionFolderURL: sessionFolderURL
            )
            AppLogger.file(.warning, category: "recording", "audio reprocess failed recording_id=\(recording.id) error=\(String(describing: error))")
            return AudioReprocessResult(
                recordingID: recording.id,
                title: recording.title,
                status: .failed,
                message: "Balanced audio failed: \(String(describing: error))",
                balancedAudioURL: balancedURL,
                analysisURL: analysisURL
            )
        }
    }

    private func makeAudioMetadata(
        processing: AudioProcessingMetadata,
        audioTracks: [AudioTrackMetadata],
        microphoneAnalysis: AudioLevelAnalysis,
        systemAnalysis: AudioLevelAnalysis
    ) -> RecordingAudioMetadata {
        RecordingAudioMetadata(
            processing: processing,
            health: AudioHealthEvaluator.evaluate(
                audioTracks: audioTracks,
                processing: processing,
                microphoneAnalysis: microphoneAnalysis,
                systemAnalysis: systemAnalysis
            )
        )
    }

    private func writeAnalysis(
        recordingID: String,
        microphone: AudioLevelAnalysis,
        system: AudioLevelAnalysis,
        plan: AudioBalancePlan,
        output: AudioLevelingOutputAnalysis?,
        to url: URL
    ) throws {
        try AudioLevelingAnalysisCodec.write(
            AudioLevelingAnalysisDocument(
                recordingID: recordingID,
                mode: mode,
                microphone: microphone,
                system: system,
                plan: plan,
                output: output
            ),
            to: url
        )
    }

    private func upsertingSourceTracks(
        in tracks: [AudioTrackMetadata],
        microphone: AudioLevelAnalysis,
        system: AudioLevelAnalysis
    ) -> [AudioTrackMetadata] {
        var updated = tracks
        updated = upserting(sourceTrack(kind: "microphone", analysis: microphone), into: updated)
        updated = upserting(sourceTrack(kind: "system", analysis: system), into: updated)
        return updated
    }

    private func sourceTrack(kind: String, analysis: AudioLevelAnalysis) -> AudioTrackMetadata {
        AudioTrackMetadata(
            kind: kind,
            relativePath: analysis.relativePath,
            durationSec: analysis.durationSec > 0 ? analysis.durationSec : nil,
            fileSizeBytes: analysis.fileSizeBytes > 0 ? analysis.fileSizeBytes : nil,
            status: analysis.exists && analysis.fileSizeBytes > 0 ? "completed" : "missing",
            signal: AudioSignalMetadata(
                hadSignal: analysis.hasUsableSignal,
                approximateSilenceRatio: analysis.silenceRatio,
                clippingDetected: analysis.clippingDetected
            ),
            error: analysis.exists ? nil : "File is missing or empty"
        )
    }

    private func upserting(
        _ track: AudioTrackMetadata,
        into tracks: [AudioTrackMetadata]
    ) -> [AudioTrackMetadata] {
        var updated = tracks.filter { $0.kind != track.kind }
        updated.append(track)
        return updated.sorted { lhs, rhs in
            trackSortIndex(lhs.kind) < trackSortIndex(rhs.kind)
        }
    }

    private func trackSortIndex(_ kind: String) -> Int {
        switch kind {
        case "microphone":
            return 0
        case "system":
            return 1
        case "mixed":
            return 2
        case "mixed_balanced":
            return 3
        default:
            return 10
        }
    }
}
