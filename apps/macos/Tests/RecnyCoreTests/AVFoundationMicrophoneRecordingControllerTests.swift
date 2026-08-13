import AVFoundation
import ScreenCaptureKit
import Testing
@testable import RecnyCore

@MainActor
struct AVFoundationMicrophoneRecordingControllerTests {
    @Test
    func usesM4AAAC48kMonoSettings() {
        let settings = AVFoundationMicrophoneRecordingController.audioRecorderSettings

        #expect(settings[AVFormatIDKey] as? Int == Int(kAudioFormatMPEG4AAC))
        #expect(settings[AVSampleRateKey] as? Double == 48_000)
        #expect(settings[AVNumberOfChannelsKey] as? Int == 1)
        #expect(settings[AVEncoderBitRateKey] as? Int == 128_000)
    }

    @Test
    func usesCoreAudioTapForSystemAudioByDefault() {
        #expect(ScreenCaptureKitSystemAudioRecorder.captureBackendName == "Core Audio process tap")
    }

    @Test
    func systemAudioUsesSynchronousFileWritesForLongCalls() {
        #expect(ScreenCaptureKitSystemAudioRecorder.audioFileWriteOperationName == "ExtAudioFileWrite")
    }

    @Test
    func systemAudioPermissionRequestDoesNotRequireScreenCaptureKit() {
        #expect(!ScreenCaptureKitSystemAudioRecorder.requiresScreenCaptureKitPermissionRequest)
    }

    @Test
    func systemAudioPermissionProbeSucceedsOnlyAfterRealFramesArrive() async throws {
        let events = PermissionProbeEventRecorder()
        let frames = AtomicFrameCounter()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecnyPermissionProbe-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let runner = SystemAudioPermissionProbeRunner(
            temporaryDirectory: tempDirectory,
            startCapture: { outputURL in
                events.append("start:\(outputURL.pathExtension)")
            },
            stopCapture: {
                events.append("stop")
            },
            cleanupOutput: { outputURL in
                events.append("cleanup:\(outputURL.pathExtension)")
            },
            sleepNanoseconds: { nanoseconds in
                events.append("wait:\(nanoseconds)")
                // Simulate macOS delivering samples after the second poll —
                // i.e. user clicked Allow at some point during the wait.
                if events.values.filter({ $0.hasPrefix("wait:") }).count >= 2 {
                    frames.set(4096)
                }
            },
            frameCount: {
                frames.value
            },
            pollIntervalNanoseconds: 100,
            maxWaitNanoseconds: 1_000
        )

        try await runner.requestAccess()

        #expect(events.values == [
            "start:m4a",
            "wait:100",
            "wait:100",
            "stop",
            "cleanup:m4a"
        ])
    }

    @Test
    func systemAudioPermissionProbeFailsWhenNoSamplesArriveWithinTimeout() async {
        let events = PermissionProbeEventRecorder()
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecnyPermissionProbe-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        let runner = SystemAudioPermissionProbeRunner(
            temporaryDirectory: tempDirectory,
            startCapture: { _ in events.append("start") },
            stopCapture: { events.append("stop") },
            cleanupOutput: { _ in events.append("cleanup") },
            sleepNanoseconds: { _ in events.append("wait") },
            frameCount: { 0 },
            pollIntervalNanoseconds: 50,
            maxWaitNanoseconds: 150
        )

        await #expect(throws: RecordingControllerError.self) {
            try await runner.requestAccess()
        }

        // Cleanup must always run, even on timeout.
        #expect(events.values.contains("stop"))
        #expect(events.values.contains("cleanup"))
    }

    @Test
    func keepsLegacyScreenCaptureKitSettingsDocumentedWithoutMicrophoneCapture() {
        let configuration = ScreenCaptureKitSystemAudioRecorder.streamConfiguration()
        let writerSettings = ScreenCaptureKitSystemAudioRecorder.assetWriterAudioSettings

        #expect(configuration.capturesAudio)
        #expect(!configuration.captureMicrophone)
        #expect(configuration.sampleRate == 48_000)
        #expect(configuration.channelCount == 2)
        #expect(writerSettings[AVFormatIDKey] as? Int == Int(kAudioFormatMPEG4AAC))
        #expect(writerSettings[AVSampleRateKey] as? Double == 48_000)
        #expect(writerSettings[AVNumberOfChannelsKey] as? Int == 2)
    }
}

private final class PermissionProbeEventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storedValues: [String] = []

    var values: [String] {
        lock.withLock {
            storedValues
        }
    }

    func append(_ value: String) {
        lock.withLock {
            storedValues.append(value)
        }
    }
}

private final class AtomicFrameCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Int64 = 0

    var value: Int64 {
        lock.withLock { stored }
    }

    func set(_ value: Int64) {
        lock.withLock { stored = value }
    }
}
