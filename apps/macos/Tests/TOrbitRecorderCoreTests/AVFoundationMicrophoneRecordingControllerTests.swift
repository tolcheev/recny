import AVFoundation
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
}
