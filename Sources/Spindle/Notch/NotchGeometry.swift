import AppKit

/// Where the notch is, in screen coordinates.
struct NotchMetrics: Equatable {
    var screenFrame: CGRect
    /// Width of the physical camera housing, or a synthesised pill on Macs without one.
    var notchWidth: CGFloat
    /// Height of the menu bar strip the notch occupies.
    var notchHeight: CGFloat
    /// Horizontal centre of the notch in screen coordinates.
    var notchCenterX: CGFloat
    var isRealNotch: Bool

    /// Fallback size for external displays and pre-2021 Macs, where we draw a pill that
    /// behaves like a notch but sits under the menu bar.
    static let syntheticWidth: CGFloat = 190

    static func current(for screen: NSScreen? = nil) -> NotchMetrics {
        let screen = screen ?? NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
        let frame = screen.frame

        let topInset = screen.safeAreaInsets.top
        let left = screen.auxiliaryTopLeftArea?.width ?? 0
        let right = screen.auxiliaryTopRightArea?.width ?? 0

        // A real notch shows up as two auxiliary areas that don't span the full width.
        let hasNotch = topInset > 0 && left > 0 && right > 0 && (left + right) < frame.width

        if hasNotch {
            let width = frame.width - left - right
            return NotchMetrics(screenFrame: frame,
                                notchWidth: width,
                                notchHeight: topInset,
                                notchCenterX: frame.minX + left + width / 2,
                                isRealNotch: true)
        }

        let menuBarHeight = max(NSStatusBar.system.thickness, 24)
        return NotchMetrics(screenFrame: frame,
                            notchWidth: syntheticWidth,
                            notchHeight: menuBarHeight,
                            notchCenterX: frame.midX,
                            isRealNotch: false)
    }

    /// Window frame large enough to hold the expanded panel, anchored to the screen top.
    func windowFrame() -> CGRect {
        let width = max(Theme.expandedWidth, notchWidth + Theme.collapsedWingWidth * 2) + 80
        let height = Theme.expandedHeight + 60
        return CGRect(x: notchCenterX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The area the cursor must reach for the panel to open, in screen coordinates.
    func hoverZone() -> CGRect {
        let width = notchWidth + Theme.collapsedWingWidth * 2
        return CGRect(x: notchCenterX - width / 2,
                      y: screenFrame.maxY - notchHeight,
                      width: width,
                      height: notchHeight)
    }

    /// Once open, the cursor may roam over the whole panel without it closing.
    func liveZone() -> CGRect {
        CGRect(x: notchCenterX - Theme.expandedWidth / 2 - 12,
               y: screenFrame.maxY - Theme.expandedHeight - 12,
               width: Theme.expandedWidth + 24,
               height: Theme.expandedHeight + 12)
    }
}
