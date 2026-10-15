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
    public var isExpanded: Bool
    public var isZenHidden: Bool

    public init(pillFrame: CGRect, hoverZone: CGRect, isExpanded: Bool, isZenHidden: Bool) {
        self.pillFrame = pillFrame
        self.hoverZone = hoverZone
        self.isExpanded = isExpanded
        self.isZenHidden = isZenHidden
    }

    public var userInfo: [String: Any] {
        [
            "pill": NSStringFromRect(pillFrame),
            "hover": NSStringFromRect(hoverZone),
            "expanded": isExpanded,
            "zen": isZenHidden
        ]
    }

    public init?(userInfo: [String: Any]) {
        guard let pill = userInfo["pill"] as? String,
              let hover = userInfo["hover"] as? String else { return nil }
        pillFrame = NSRectFromString(pill)
        hoverZone = NSRectFromString(hover)
        isExpanded = userInfo["expanded"] as? Bool ?? false
        isZenHidden = userInfo["zen"] as? Bool ?? false
    }
}
