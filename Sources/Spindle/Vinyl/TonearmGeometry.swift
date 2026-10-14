import CoreGraphics
import Foundation

/// Maps between playback progress and the tonearm's rotation.
///
/// Rather than faking it with a linear angle sweep, this solves the actual pivot
/// geometry: the stylus is the intersection of the arm's reach circle (centred on the
/// pivot) with the groove circle (centred on the spindle). The payoff is that dragging
/// the arm inverts exactly — the groove you drop the needle on is the one you hear.
struct TonearmGeometry {
    /// Spindle, in container coordinates (y grows downward).
    var center: CGPoint
    /// Record radius.
    var radius: CGFloat
    /// Effective arm length, pivot to stylus.
    var length: CGFloat
    /// Arm pivot, up and to the right of the platter.
    var pivot: CGPoint

    init(center: CGPoint, radius: CGFloat) {
        self.center = center
        self.radius = radius
        self.pivot = CGPoint(x: center.x + radius * 1.10, y: center.y - radius * 0.92)
        self.length = radius * 1.50
    }

    /// Groove radius at progress 0 — the lead-in, just inside the edge.
    var outerGroove: CGFloat { radius * 0.93 }
    /// Groove radius at progress 1 — the run-out, at the label edge.
    var innerGroove: CGFloat { radius * 0.45 }
    /// Where the arm parks when nothing is playing: clear of the record.
    var restGroove: CGFloat { radius * 1.25 }

    private var pivotDistance: CGFloat {
        hypot(center.x - pivot.x, center.y - pivot.y)
    }

    /// Direction from the pivot toward the spindle, in radians.
    private var bearing: CGFloat {
        atan2(center.y - pivot.y, center.x - pivot.x)
    }

    /// Arm angle (radians, screen coordinates) that puts the stylus on groove `distance`.
    func angle(forGrooveRadius distance: CGFloat) -> CGFloat {
        let d = pivotDistance
        let l = length
        guard d > 0, l > 0 else { return bearing }

        let cosine = (d * d + l * l - distance * distance) / (2 * d * l)
        let clamped = min(max(cosine, -1), 1)
        // Subtracting keeps the stylus on the near side of the platter, which is the
        // side a right-mounted arm actually sweeps.
        return bearing - acos(clamped)
    }

    /// Inverse of `angle(forGrooveRadius:)`.
    func grooveRadius(forAngle angle: CGFloat) -> CGFloat {
        let d = pivotDistance
        let l = length
        let alpha = bearing - angle
        let squared = d * d + l * l - 2 * d * l * cos(alpha)
        return sqrt(max(squared, 0))
    }

    func angle(forProgress progress: Double) -> CGFloat {
        let t = CGFloat(min(max(progress, 0), 1))
        return angle(forGrooveRadius: outerGroove - (outerGroove - innerGroove) * t)
    }

    var restAngle: CGFloat { angle(forGrooveRadius: restGroove) }

    /// Converts a cursor position into playback progress, clamped to the record.
    func progress(forPoint point: CGPoint) -> Double {
        let angle = atan2(point.y - pivot.y, point.x - pivot.x)
        let distance = grooveRadius(forAngle: angle)
        let span = outerGroove - innerGroove
        guard span > 0 else { return 0 }
        return Double(min(max((outerGroove - distance) / span, 0), 1))
    }

    func stylusPoint(atAngle angle: CGFloat) -> CGPoint {
        CGPoint(x: pivot.x + cos(angle) * length,
                y: pivot.y + sin(angle) * length)
    }
}
