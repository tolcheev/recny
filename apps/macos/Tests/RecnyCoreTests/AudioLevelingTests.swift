import AVFoundation
import Foundation
import Testing
@testable import RecnyCore

struct AudioLevelingTests {
    @Test
    func quietMicAndLoudSystemBoostsMicWithoutExceedingLimit() {
        let mic = Self.analysis(
            kind: .microphone,
            peakDBFS: -24,
            rmsDBFS: -42,
            silenceRatio: 0.18
        )
        let system = Self.analysis(
            kind: .system,
            peakDBFS: -3,
            rmsDBFS: -17,
            silenceRatio: 0.08
        )

        let plan = AudioBalancePlanner().plan(microphone: mic, system: system, mode: .balanced)

        #expect(plan.microphoneGainDB > 0)
        #expect(plan.microphoneGainDB <= 12)
        #expect(plan.systemGainDB <= 0)
        #expect(plan.limiterRequired)
        #expect(plan.limiterCeilingDBFS == -1)
    }

    @Test
    func loudMicAndQuietSystemBoostsSystemTrack() {
        let mic = Self.analysis(
            kind: .microphone,
            peakDBFS: -4,
            rmsDBFS: -18,
            silenceRatio: 0.12
        )
        let system = Self.analysis(
            kind: .system,
            peakDBFS: -27,
            rmsDBFS: -43,
            silenceRatio: 0.22
        )

        let plan = AudioBalancePlanner().plan(microphone: mic, system: system, mode: .balanced)

        #expect(plan.systemGainDB > 0)
        #expect(plan.systemGainDB <= 12)
        #expect(plan.microphoneGainDB <= 0)
    }

    @Test
    func silentMicIsNotBoostedAggressively() {
        let mic = Self.analysis(
            kind: .microphone,
            peakDBFS: -54,
            rmsDBFS: -62,
            silenceRatio: 0.99,
            hasUsableSignal: false
        )
        let system = Self.analysis(
            kind: .system,
            peakDBFS: -8,
            rmsDBFS: -24,
            silenceRatio: 0.1
        )

        let plan = AudioBalancePlanner().plan(microphone: mic, system: system, mode: .balanced)

        #expect(plan.microphoneGainDB == 0)
        #expect(plan.warnings.contains(.microphoneSeemsSilent))
    }

    @Test
    func missingSystemCreatesMicOnlyPlanGracefully() {
        let mic = Self.analysis(
            kind: .microphone,
            peakDBFS: -10,
            rmsDBFS: -27,
            silenceRatio: 0.2
        )

        let plan = AudioBalancePlanner().plan(microphone: mic, system: nil, mode: .balanced)

        #expect(plan.microphoneGainDB.isFinite)
        #expect(plan.systemGainDB == 0)
        #expect(plan.status == .partial)
        #expect(plan.usedSourceKinds == ["microphone"])
    }

    @Test
    func clippingRequiresLimiterAndWarning() {
        let mic = Self.analysis(
            kind: .microphone,
            peakDBFS: -0.1,
            rmsDBFS: -15,
            silenceRatio: 0.05,
            clippingDetected: true
        )
        let system = Self.analysis(
            kind: .system,
            peakDBFS: -12,
            rmsDBFS: -26,
            silenceRatio: 0.2
        )

        let plan = AudioBalancePlanner().plan(microphone: mic, system: system, mode: .balanced)

        #expect(plan.limiterRequired)
        #expect(plan.warnings.contains(.microphoneClippingDetected))
        #expect(plan.microphoneGainDB <= 0)
    }

    @Test
    func metadataStoresAudioProcessingSummary() throws {
        let processing = AudioProcessingMetadata(
            balancedMixStatus: .done,
            balancedMixPath: "export/mixed_balanced.m4a",
            analysisPath: "analysis/audio_analysis.json",
            microphoneGainDB: 4.5,
            systemGainDB: -2,
            warnings: ["Microphone track was boosted for balanced playback."]
        )
        let metadata = RecordingMetadata(
            id: "rec_leveling",
            title: "Leveling",
            startedAt: "2026-05-24T00:00:00Z",
            endedAt: "2026-05-24T00:01:10Z",
            durationSec: 70,
            audio: RecordingAudioMetadata(processing: processing)
        )

        let data = try RecordingMetadataCodec().encode(metadata)
        let decoded = try RecordingMetadataCodec().decode(data)

        #expect(decoded.audio.processing.balancedMixStatus == .done)
        #expect(decoded.audio.processing.balancedMixPath == "export/mixed_balanced.m4a")
        #expect(decoded.audio.processing.analysisPath == "analysis/audio_analysis.json")
        #expect(decoded.audio.processing.microphoneGainDB == 4.5)
        #expect(decoded.audio.processing.systemGainDB == -2)
    }

    @Test
    func analyzerReportsUsableSignalForFixtureAudio() throws {
        let analysis = try AudioLevelAnalyzer().analyze(url: Self.fixtureAudioURL(), kind: .microphone)

        #expect(analysis.durationSec > 0)
        #expect(analysis.peakDBFS.isFinite)
        #expect(analysis.rmsDBFS.isFinite)
        #expect(analysis.approximateLoudnessDB.isFinite)
        #expect(analysis.silenceRatio >= 0)
        #expect(analysis.silenceRatio <= 1)
        #expect(analysis.hasUsableSignal)
    }

    @Test
    func balancedMixerCreatesOutputFromSingleAvailableTrack() async throws {
        let root = Self.testOutputFolder()
        let sourceURL = root.appendingPathComponent("source", isDirectory: true)
        let exportURL = root.appendingPathComponent("export", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: exportURL, withIntermediateDirectories: true)

        let micURL = sourceURL.appendingPathComponent("mic.aiff")
        let systemURL = sourceURL.appendingPathComponent("system.m4a")
        let balancedURL = exportURL.appendingPathComponent("mixed_balanced.m4a")
        try FileManager.default.copyItem(at: Self.fixtureAudioURL(), to: micURL)

        let micAnalysis = try AudioLevelAnalyzer().analyze(url: micURL, kind: .microphone)
        let plan = AudioBalancePlanner().plan(
            microphone: micAnalysis,
            system: nil,
            mode: .balanced
        )

        let result = try await AudioBalancedMixer().createBalancedMix(
            micURL: micURL,
            systemURL: systemURL,
            outputURL: balancedURL,
            plan: plan
        )

        #expect(FileManager.default.fileExists(atPath: balancedURL.path(percentEncoded: false)))
        #expect(result.fileSizeBytes > 0)
        #expect(result.track.kind == "mixed_balanced")
        #expect(result.track.relativePath == "export/mixed_balanced.m4a")
        #expect(result.usedSourceKinds == ["microphone"])
    }

    private static func analysis(
        kind: AudioLevelTrackKind,
        durationSec: Double = 60,
        peakDBFS: Double,
        rmsDBFS: Double,
        silenceRatio: Double,
        clippingDetected: Bool = false,
        hasUsableSignal: Bool = true
    ) -> AudioLevelAnalysis {
        AudioLevelAnalysis(
            kind: kind,
            relativePath: kind == .microphone ? "source/mic.m4a" : "source/system.m4a",
            exists: true,
            fileSizeBytes: 1024,
            durationSec: durationSec,
            peakDBFS: peakDBFS,
            rmsDBFS: rmsDBFS,
            approximateLoudnessDB: rmsDBFS,
            silenceRatio: silenceRatio,
            clippingDetected: clippingDetected,
            hasUsableSignal: hasUsableSignal
        )
    }

    private static func fixtureAudioURL() -> URL {
        URL(fileURLWithPath: "/System/Library/Sounds/Ping.aiff")
    }

    private static func testOutputFolder() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build", isDirectory: true)
            .appendingPathComponent("audio-leveling-tests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
