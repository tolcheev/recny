import CoreGraphics
import Testing
@testable import RecnyCore

struct WindowFramePlacementTests {
    @Test
    func centersWindowInsideVisibleFrameWithMargin() {
        let frame = WindowFramePlacement.centeredFrame(
            windowSize: CGSize(width: 600, height: 400),
            visibleFrame: CGRect(x: 0, y: 0, width: 1_440, height: 900),
            margin: 40
        )

        #expect(frame == CGRect(x: 420, y: 250, width: 600, height: 400))
    }

    @Test
    func clampsOversizedWindowToVisibleFrame() {
        let frame = WindowFramePlacement.centeredFrame(
            windowSize: CGSize(width: 1_500, height: 900),
            visibleFrame: CGRect(x: 100, y: 50, width: 1_200, height: 800),
            margin: 40
        )

        #expect(frame == CGRect(x: 140, y: 90, width: 1_120, height: 720))
    }
}
