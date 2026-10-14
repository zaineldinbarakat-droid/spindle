import SwiftUI

enum Theme {
    static let defaultAccent = Color(red: 0.91, green: 0.36, blue: 0.33)

    /// The notch panel is always dark — it has to read as an extension of the bezel,
    /// so it deliberately ignores the system appearance.
    static let panel = Color.black
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.62)
    static let tertiaryText = Color.white.opacity(0.38)

    /// Corner radii for the shape that hangs below the notch.
    static let outerCornerRadius: CGFloat = 22
    static let notchCornerRadius: CGFloat = 12

    static let collapsedWingWidth: CGFloat = 92
    static let expandedWidth: CGFloat = 640
    static let expandedHeight: CGFloat = 300

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
    /// Used for the open/close of the panel — a short spring with no overshoot wobble,
    /// so the panel feels attached to the hardware rather than bouncy.
    static var notch: Animation { .spring(response: 0.34, dampingFraction: 0.82) }
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
