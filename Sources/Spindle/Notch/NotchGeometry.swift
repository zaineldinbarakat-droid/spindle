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
    /// How big the open panel is drawn, relative to its 500 × 200 pt design. The closed
    /// pill always matches the hardware notch and doesn't scale.
    var panelScale: CGFloat = 1

    /// The largest size the setting allows; the window is always big enough for it, so
    /// changing the size never resizes the window.
    static let maxPanelScale: CGFloat = 1.15

    /// The open panel's size. The strip beside the camera keeps the notch's real height;
    /// everything below it scales.
    var panelSize: CGSize {
        CGSize(width: Theme.expandedWidth * panelScale,
               height: notchHeight + (Theme.expandedHeight - notchHeight) * panelScale)
    }

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
        let width = max(Theme.expandedWidth * Self.maxPanelScale, notchWidth + Theme.collapsedWingWidth * 2) + 80
        let height = notchHeight + (Theme.expandedHeight - notchHeight) * Self.maxPanelScale + 60
        return CGRect(x: notchCenterX - width / 2,
                      y: screenFrame.maxY - height,
                      width: width,
                      height: height)
    }

    /// The area the cursor must reach for the panel to open, in screen coordinates.
    /// How far the zones reach *above* the screen. Pushed against the top edge, the
    /// cursor reports y == screenFrame.maxY exactly, which `CGRect.contains` treats
    /// as outside — so the panel thought the cursor had left, closed, and reopened a
    /// pixel later. Measured on this Mac: top edge → y 982.0, screen top 982.0.
    static let overshoot: CGFloat = 8

    func hoverZone() -> CGRect {
        let width = notchWidth + Theme.collapsedWingWidth * 2
        return CGRect(x: notchCenterX - width / 2,
                      y: screenFrame.maxY - notchHeight,
                      width: width,
                      height: notchHeight + Self.overshoot)
    }

    /// The little record in the collapsed pill's left wing.
    func collapsedRecordZone() -> CGRect {
        let wingLeft = notchCenterX - notchWidth / 2 - Theme.collapsedWingWidth
        return CGRect(x: wingLeft + Theme.notchCornerRadius - 4,
                      y: screenFrame.maxY - notchHeight,
                      width: notchHeight + 16,
                      height: notchHeight)
    }

    /// Once open, the cursor may roam over the whole panel without it closing.
    func liveZone() -> CGRect {
        let size = panelSize
        return CGRect(x: notchCenterX - size.width / 2 - 12,
                      y: screenFrame.maxY - size.height - 12,
                      width: size.width + 24,
                      height: size.height + 12 + Self.overshoot)
    }
}
