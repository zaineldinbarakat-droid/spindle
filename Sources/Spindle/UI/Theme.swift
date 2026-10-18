import SwiftUI

enum Theme {
    static let defaultAccent = Color(red: 0.91, green: 0.36, blue: 0.33)

    /// The notch panel is always dark — it has to read as an extension of the bezel,
    /// so it deliberately ignores the system appearance.
    /// Exactly #000000 in sRGB, the closest a display gets to the hardware notch.
    static let panel = Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    /// Focus-timer phases: tomato for work, two calmer greens for breaks.
    static let focusColor = Color(red: 0.93, green: 0.33, blue: 0.27)
    static let breakColor = Color(red: 0.36, green: 0.78, blue: 0.56)
    static let longBreakColor = Color(red: 0.33, green: 0.68, blue: 0.86)

    /// Walnut plinth used by the desktop widgets and the backdrop.
    static let walnutLight = Color(red: 0.36, green: 0.22, blue: 0.13)
    static let walnutDark = Color(red: 0.17, green: 0.10, blue: 0.06)
    static let cream = Color(red: 0.96, green: 0.91, blue: 0.80)

    /// Corner radii for the shape that hangs below the notch.
    static let outerCornerRadius: CGFloat = 22
    /// Matches the MacBook notch: small shoulders where it meets the top edge and
    /// gently rounded lower corners.
    static let notchCornerRadius: CGFloat = 8

    static let collapsedWingWidth: CGFloat = 64
    static let expandedWidth: CGFloat = 500
    static let expandedHeight: CGFloat = 200

    /// Vinyl sizing, expressed as fractions of the record diameter.
    enum Record {
        static let labelFraction: CGFloat = 0.38
        static let spindleFraction: CGFloat = 0.035
        static let grooveInnerFraction: CGFloat = 0.42
        static let grooveOuterFraction: CGFloat = 0.97
        static let rpm: Double = 33 + 1.0 / 3.0
    }
}

/// How content arrives and leaves inside the island, the way the Dynamic Island's
/// does: it fades while growing a touch from the top, rather than popping in. (No
/// blur: re-rendering a blur over the whole panel each frame dropped frames.)
struct IslandContent: ViewModifier {
    var progress: Double

    func body(content: Content) -> some View {
        content
            .opacity(progress)
            .scaleEffect(0.96 + 0.04 * progress, anchor: .top)
    }
}

extension AnyTransition {
    static var islandContentIn: AnyTransition {
        .modifier(active: IslandContent(progress: 0), identity: IslandContent(progress: 1))
    }

    static var notchReveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
            removal: .opacity
        )
    }
}

extension Animation {
    /// Opening, after the Dynamic Island: the shape springs out of the notch and
    /// settles with the slightest overshoot — enough to feel physical, not bouncy. A
    /// spring keeps its velocity if interrupted, so a quick in-and-out never snaps.
    static var notch: Animation { NotchMotion.current.open }
    /// Closing is quicker and doesn't overshoot: it tucks back into the hardware.
    static var notchClose: Animation { NotchMotion.current.close }
    static var notchQuick: Animation { .spring(response: 0.22, dampingFraction: 0.9) }
}

/// How the panel springs open and tucks away (Settings → Panel → Motion).
enum NotchMotion: String, CaseIterable, Identifiable {
    /// Like the rest of macOS — a menu or popover: a quick, clean grow and fade, no
    /// overshoot. The default.
    case macOS
    case snappy, smooth, bouncy

    var id: String { rawValue }
    var title: String { self == .macOS ? "macOS" : rawValue.capitalized }

    static var current: NotchMotion {
        NotchMotion(rawValue: Defaults.string(.notchMotion) ?? "") ?? .macOS
    }

    var open: Animation {
        switch self {
        case .macOS: return .spring(duration: 0.24, bounce: 0)
        case .snappy: return .spring(duration: 0.3, bounce: 0.04)
        case .smooth: return .spring(duration: 0.45, bounce: 0.12)
        case .bouncy: return .spring(duration: 0.55, bounce: 0.3)
        }
    }

    var close: Animation {
        switch self {
        case .macOS: return .easeIn(duration: 0.16)
        case .snappy: return .spring(duration: 0.24, bounce: 0)
        case .smooth: return .spring(duration: 0.38, bounce: 0.04)
        case .bouncy: return .spring(duration: 0.44, bounce: 0.14)
        }
    }

    /// The open panel's content arriving behind the growing shape.
    var contentIn: Animation {
        switch self {
        case .macOS: return .easeOut(duration: 0.18).delay(0.03)
        case .snappy: return .spring(duration: 0.28, bounce: 0).delay(0.03)
        case .smooth: return .spring(duration: 0.42, bounce: 0.08).delay(0.06)
        case .bouncy: return .spring(duration: 0.5, bounce: 0.2).delay(0.06)
        }
    }

    var contentOut: Animation { self == .macOS ? .easeIn(duration: 0.1) : .easeIn(duration: 0.12) }

    /// The closed pill's content coming back once the panel has tucked away.
    var pillIn: Animation {
        self == .macOS ? .easeOut(duration: 0.2).delay(0.1) : .spring(duration: 0.35, bounce: 0).delay(0.14)
    }
}

extension Double {
    var clockString: String {
        guard isFinite, self >= 0 else { return "0:00" }
        let total = Int(self.rounded())
        let minutes = total / 60
        let seconds = total % 60
        if minutes >= 60 {
            return String(format: "%d:%02d:%02d", minutes / 60, minutes % 60, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }
}

extension View {
    /// Shows the pointing-hand cursor while hovering, to signal "this opens something".
    func pointingHandOnHover() -> some View {
        onHover { inside in
            if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
