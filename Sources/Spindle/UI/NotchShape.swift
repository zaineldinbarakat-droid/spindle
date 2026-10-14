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

        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Inverted corner: curls outward into the bezel.
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top * 0.2, y: rect.minY + top)
        )

        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )

        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top * 0.2, y: rect.minY + top)
        )

        path.closeSubpath()
        return path
    }
}
