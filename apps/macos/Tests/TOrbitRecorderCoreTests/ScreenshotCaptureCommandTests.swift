import Testing
@testable import TOrbitRecorderCore

struct ScreenshotCaptureCommandTests {
    @Test
    func fullScreenCaptureUsesNonInteractiveScreencaptureArguments() {
        let arguments = ScreenshotCaptureCommand.fullScreenArguments(
            outputPath: "/tmp/recording/screenshots/screenshot.png"
        )

        #expect(arguments == ["-x", "/tmp/recording/screenshots/screenshot.png"])
        #expect(!arguments.contains("-i"))
    }
}
