import Foundation
import Testing
@testable import RecnyCore

struct RecordingDerivedArtifactPathsTests {
    @Test
    func buildsStableTrimAndScreenshotPathsInsideSessionFolder() {
        let sessionFolder = URL(fileURLWithPath: "/tmp/recording")
        let date = Date(timeIntervalSince1970: 0)

        let clipURL = RecordingDerivedArtifactPaths.trimmedAudioURL(
            sessionFolderURL: sessionFolder,
            date: date
        )
        let screenshotURL = RecordingDerivedArtifactPaths.screenshotURL(
            sessionFolderURL: sessionFolder,
            date: date
        )

        #expect(clipURL.path(percentEncoded: false) == "/tmp/recording/export/clip_1970-01-01_00-00-00-000.m4a")
        #expect(screenshotURL.path(percentEncoded: false) == "/tmp/recording/screenshots/screenshot_1970-01-01_00-00-00-000.png")
    }
}
