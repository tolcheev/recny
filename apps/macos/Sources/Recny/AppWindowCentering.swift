import AppKit
import RecnyCore

@MainActor
enum AppWindowCentering {
    static func centerAfterPresentation(_ window: NSWindow, preferredScreen: NSScreen? = nil) {
        center(window, preferredScreen: preferredScreen, reason: "presentation")
        window.contentView?.layoutSubtreeIfNeeded()
        center(window, preferredScreen: preferredScreen, reason: "layout")

        DispatchQueue.main.async { [weak window] in
            guard let window else {
                return
            }
            center(window, preferredScreen: preferredScreen, reason: "next_runloop")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak window] in
            guard let window else {
                return
            }
            center(window, preferredScreen: preferredScreen, reason: "delayed_layout")
        }
    }

    static func center(_ window: NSWindow, preferredScreen: NSScreen? = nil, reason: String = "manual") {
        guard let screen = preferredScreen ?? NSScreen.main ?? window.screen else {
            window.center()
            return
        }

        let frame = WindowFramePlacement.centeredFrame(
            windowSize: window.frame.size,
            visibleFrame: screen.visibleFrame
        )
        window.setFrame(frame, display: true)
        AppLogger.file(
            .info,
            category: "app",
            "window centered reason=\(reason) title=\(window.title) frame=\(Self.describe(frame)) visible=\(Self.describe(screen.visibleFrame))"
        )
    }

    private static func describe(_ rect: CGRect) -> String {
        "x=\(Int(rect.origin.x)) y=\(Int(rect.origin.y)) w=\(Int(rect.size.width)) h=\(Int(rect.size.height))"
    }
}
