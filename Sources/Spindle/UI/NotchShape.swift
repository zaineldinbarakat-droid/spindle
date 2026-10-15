import SwiftUI

/// The panel outline: square at the top where it meets the bezel, rounded at the bottom,
/// with the inverted fillets that make it read as spilling out of the notch.
struct NotchShape: Shape {
    var topRadius: CGFloat = Theme.notchCornerRadius
    var bottomRadius: CGFloat = Theme.outerCornerRadius

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(topRadius, bottomRadius) }
        set {
            topRadius = newValue.first
            bottomRadius = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let top = min(topRadius, rect.height / 2)
        let bottom = min(bottomRadius, rect.height / 2, rect.width / 2)
        // Bézier handle length for a quarter circle.
        let k: CGFloat = 0.552

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Left flare: leaves the screen edge horizontally and turns smoothly downward,
        // like the hardware notch meeting the bezel. (The old quadratic curve left a
        // flat step here — the "bump" visible as the panel opened.)
        path.addCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control1: CGPoint(x: rect.minX + top * k, y: rect.minY),
            control2: CGPoint(x: rect.minX + top, y: rect.minY + top * (1 - k))
        )

        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control1: CGPoint(x: rect.minX + top, y: rect.maxY - bottom * (1 - k)),
            control2: CGPoint(x: rect.minX + top + bottom * (1 - k), y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control1: CGPoint(x: rect.maxX - top - bottom * (1 - k), y: rect.maxY),
            control2: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom * (1 - k))
        )

        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        // Right flare, mirrored.
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control1: CGPoint(x: rect.maxX - top, y: rect.minY + top * (1 - k)),
            control2: CGPoint(x: rect.maxX - top * k, y: rect.minY)
        )

        path.closeSubpath()
        return path
    }
}
