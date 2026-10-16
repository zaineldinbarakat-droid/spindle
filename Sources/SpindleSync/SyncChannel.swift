import Foundation
import CoreGraphics

/// How Spindle (the notch player) and Sleeve (the menu bar manager) coordinate.
///
/// Both apps draw in the same few hundred points at the top of the screen, so each
/// tells the other what it is doing over distributed notifications. Nothing is
/// required: either app works alone, and the messages are ignored if the other isn't
/// running.
///
/// What they agree on:
/// - Spindle publishes the strip it occupies beside the notch. Sleeve keeps its
///   hover-to-reveal zone and its menu bar styling out of that strip.
/// - Only one dropdown is open at a time: opening Sleeve's bar closes Spindle's
///   panel, and vice versa.
/// - Sleeve's Zen mode hides Spindle's notch pill too.
public enum SyncChannel {
    public static let spindleBundleID = "com.spindle.notch"
    public static let sleeveBundleID = "com.spindle.sleeve"

    /// Spindle → Sleeve: `SpindleState` in userInfo.
    public static let spindleState = Notification.Name("com.spindle.sync.spindleState")
    /// Sleeve → Spindle: please re-send your state (sent when Sleeve launches).
    public static let requestSpindleState = Notification.Name("com.spindle.sync.requestSpindleState")
    /// Sleeve → Spindle: `["enabled": Bool]`.
    public static let zenMode = Notification.Name("com.spindle.sync.zen")
    /// Sleeve → Spindle: `["open": Bool]`. Sleeve's dropdown bar opened or closed.
    public static let sleeveBar = Notification.Name("com.spindle.sync.sleeveBar")
    /// Sleeve → Spindle: Sleeve quit; drop any state it had imposed (e.g. Zen).
    public static let sleeveTerminated = Notification.Name("com.spindle.sync.sleeveTerminated")
    /// Spindle → Sleeve: about to add its menu bar icon. An icon added while Sleeve has
    /// the other apps hidden lands among Apple's icons, so Sleeve shows them all for a
    /// moment. (macOS doesn't announce the launch of a menu-bar-only app like Spindle.)
    public static let spindleAddingIcon = Notification.Name("com.spindle.sync.spindleAddingIcon")

    public static func post(_ name: Notification.Name, _ info: [String: Any] = [:]) {
        DistributedNotificationCenter.default().postNotificationName(
            name, object: nil, userInfo: info, deliverImmediately: true)
    }

    @discardableResult
    public static func observe(_ name: Notification.Name,
                               _ handler: @escaping ([String: Any]) -> Void) -> NSObjectProtocol {
        DistributedNotificationCenter.default().addObserver(forName: name, object: nil, queue: .main) { note in
            handler((note.userInfo as? [String: Any]) ?? [:])
        }
    }
}

/// What Spindle tells Sleeve about the notch area. Rects are in global screen
/// coordinates (AppKit, origin bottom-left).
public struct SpindleState: Equatable {
    /// The collapsed pill's full extent: both wings plus the notch between them. Zero
    /// when the pill is hidden.
    public var pillFrame: CGRect
    /// Where hovering opens Spindle's panel.
    public var hoverZone: CGRect
    /// The open panel's area (zero while closed). Its top strip runs along the menu
    /// bar, so Sleeve must stay out of it too.
    public var panelFrame: CGRect
    public var isExpanded: Bool
    public var isZenHidden: Bool
    /// The current song's colour (sRGB components), for Sleeve's "Album" menu bar tint.
    public var accent: [Double]?

    public init(pillFrame: CGRect, hoverZone: CGRect, panelFrame: CGRect = .zero,
                isExpanded: Bool, isZenHidden: Bool, accent: [Double]? = nil) {
        self.pillFrame = pillFrame
        self.hoverZone = hoverZone
        self.panelFrame = panelFrame
        self.isExpanded = isExpanded
        self.isZenHidden = isZenHidden
        self.accent = accent
    }

    public var userInfo: [String: Any] {
        [
            "pill": NSStringFromRect(pillFrame),
            "hover": NSStringFromRect(hoverZone),
            "panel": NSStringFromRect(panelFrame),
            "expanded": isExpanded,
            "zen": isZenHidden,
            "accent": accent ?? []
        ]
    }

    public init?(userInfo: [String: Any]) {
        guard let pill = userInfo["pill"] as? String,
              let hover = userInfo["hover"] as? String else { return nil }
        pillFrame = NSRectFromString(pill)
        hoverZone = NSRectFromString(hover)
        panelFrame = (userInfo["panel"] as? String).map(NSRectFromString) ?? .zero
        isExpanded = userInfo["expanded"] as? Bool ?? false
        isZenHidden = userInfo["zen"] as? Bool ?? false
        let components = userInfo["accent"] as? [Double] ?? []
        accent = components.count == 3 ? components : nil
    }
}
