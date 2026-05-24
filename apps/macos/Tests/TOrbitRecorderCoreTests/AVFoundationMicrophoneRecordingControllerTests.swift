import AVFoundation
import ScreenCaptureKit
import Testing
@testable import TOrbitRecorderCore

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
