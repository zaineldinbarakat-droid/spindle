import SwiftUI

enum Theme {
    static let defaultAccent = Color(red: 0.91, green: 0.36, blue: 0.33)

    /// The notch panel is always dark — it has to read as an extension of the bezel,
    /// so it deliberately ignores the system appearance.
    static let panel = Color.black
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
    static let outerCornerRadius: CGFloat = 24
    static let notchCornerRadius: CGFloat = 12

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

extension AnyTransition {
    static var notchReveal: AnyTransition {
        .asymmetric(
            insertion: .opacity.combined(with: .scale(scale: 0.94, anchor: .top)),
            removal: .opacity
        )
    }
}

extension Animation {
    /// Used for the open/close of the panel. Critically damped-ish: the shape grows out
    /// of the notch and settles without a wobble, so it feels attached to the hardware.
    static var notch: Animation { .spring(response: 0.42, dampingFraction: 0.86) }
    static var notchQuick: Animation { .spring(response: 0.22, dampingFraction: 0.9) }
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
