import SwiftUI

/// The tonearm, drawn from the pivot outward, with drag-to-scrub on the arm itself.
///
/// The gesture reads coordinates in the turntable's named coordinate space rather than
/// the arm's own, because the arm is rotated — reading local coordinates would feed the
/// rotation back into the angle calculation and make the drag chase itself.
struct TonearmView: View {
    var geometry: TonearmGeometry
    var progress: Double
    var isEngaged: Bool
    var accent: Color
    var coordinateSpace: String

    var onScrubBegan: (Double) -> Void
    var onScrubChanged: (Double) -> Void
    var onScrubEnded: () -> Void

    @State private var isDragging = false

    private var angle: CGFloat {
        if isDragging || isEngaged {
            return geometry.angle(forProgress: progress)
        }
        return geometry.restAngle
    }

    private var armLength: CGFloat { geometry.length }
    private var counterweightLength: CGFloat { armLength * 0.34 }

    var body: some View {
        ZStack {
            armAssembly
                // Only the arm itself is grabbable. Without this the gesture would claim
                // the whole bounding square and swallow clicks on the record beneath it.
                .contentShape(ArmHitArea(length: armLength))
                .gesture(scrubGesture)
                .rotationEffect(.radians(Double(angle)))
                .animation(isDragging ? nil : .spring(response: 0.55, dampingFraction: 0.75),
                           value: angle)

            pivotHousing
                .allowsHitTesting(false)
        }
        .frame(width: armLength * 2, height: armLength * 2)
        .position(geometry.pivot)
    }

    // MARK: - Pieces

    /// Laid out in a square centred on the pivot so that rotation needs no anchor maths:
    /// the arm runs along +x, the counterweight along -x.
    private var armAssembly: some View {
        ZStack {
            // Counterweight stub behind the pivot.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.55), Color(white: 0.30)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: counterweightLength, height: armLength * 0.045)
                .offset(x: -counterweightLength / 2)

            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.62), Color(white: 0.28)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: armLength * 0.13, height: armLength * 0.13)
                .offset(x: -counterweightLength)

            // Main arm tube.
            Capsule()
                .fill(LinearGradient(colors: [Color(white: 0.78), Color(white: 0.42), Color(white: 0.62)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: armLength * 0.90, height: armLength * 0.032)
                .offset(x: armLength * 0.45)

            headshell
                .offset(x: armLength * 0.93)
        }
        .frame(width: armLength * 2, height: armLength * 2)
        .shadow(color: .black.opacity(0.55), radius: armLength * 0.03, x: 0, y: armLength * 0.02)
    }

    private var headshell: some View {
        ZStack {
            RoundedRectangle(cornerRadius: armLength * 0.018, style: .continuous)
                .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.14)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: armLength * 0.16, height: armLength * 0.075)

            // Stylus: a small wedge under the leading edge of the headshell.
            Triangle()
                .fill(isEngaged ? accent : Color(white: 0.6))
                .frame(width: armLength * 0.030, height: armLength * 0.045)
                .offset(x: armLength * 0.062, y: armLength * 0.052)
        }
        .rotationEffect(.degrees(18))   // classic offset angle of the cartridge
    }

    private var pivotHousing: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.48), Color(white: 0.18)],
                                     center: .topLeading,
                                     startRadius: 0,
                                     endRadius: armLength * 0.12))
                .frame(width: armLength * 0.17, height: armLength * 0.17)

            Circle()
                .strokeBorder(Color.white.opacity(0.22), lineWidth: 1)
                .frame(width: armLength * 0.17, height: armLength * 0.17)
        }
        .shadow(color: .black.opacity(0.5), radius: armLength * 0.02, y: armLength * 0.01)
    }

    // MARK: - Scrubbing

    private var scrubGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named(coordinateSpace))
            .onChanged { value in
                let fraction = geometry.progress(forPoint: value.location)
                if !isDragging {
                    isDragging = true
                    onScrubBegan(fraction)
                } else {
                    onScrubChanged(fraction)
                }
            }
            .onEnded { _ in
                isDragging = false
                onScrubEnded()
            }
    }
}

/// Grab area for the drag gesture: a capsule running from the counterweight to the
/// headshell, so the arm can be picked up anywhere along its length.
struct ArmHitArea: Shape {
    var length: CGFloat

    func path(in rect: CGRect) -> Path {
        let body = CGRect(x: rect.midX - length * 0.42,
                          y: rect.midY - length * 0.080,
                          width: length * 1.46,
                          height: length * 0.160)
        return Capsule().path(in: body)
    }
}

/// Stylus wedge.
struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
