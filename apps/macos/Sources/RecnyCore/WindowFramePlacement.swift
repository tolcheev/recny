import CoreGraphics

public enum WindowFramePlacement {
    public static func centeredFrame(
        windowSize: CGSize,
        visibleFrame: CGRect,
        margin: CGFloat = 40
    ) -> CGRect {
        let usableFrame = insetFrame(visibleFrame, margin: margin)
        let width = min(windowSize.width, usableFrame.width)
        let height = min(windowSize.height, usableFrame.height)
        let x = usableFrame.minX + ((usableFrame.width - width) / 2)
        let y = usableFrame.minY + ((usableFrame.height - height) / 2)

        return CGRect(
            x: x.rounded(.down),
            y: y.rounded(.down),
            width: width.rounded(.down),
            height: height.rounded(.down)
        )
    }

    private static func insetFrame(_ frame: CGRect, margin: CGFloat) -> CGRect {
        guard margin > 0,
              frame.width > margin * 2,
              frame.height > margin * 2
        else {
            return frame
        }

        return frame.insetBy(dx: margin, dy: margin)
    }
}
