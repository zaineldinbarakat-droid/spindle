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
    /// The thinnest line worth drawing at this size.
    private var hairline: CGFloat { max(armLength * 0.004, 0.4) }

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

    /// Polished chrome across a tube's thickness: dark edges, a hard highlight just
    /// above the middle where the lamp catches it.
    private static let chrome = Gradient(stops: [
        .init(color: Color(white: 0.22), location: 0.00),
        .init(color: Color(white: 0.95), location: 0.30),
        .init(color: Color(white: 0.66), location: 0.48),
        .init(color: Color(white: 0.38), location: 0.80),
        .init(color: Color(white: 0.16), location: 1.00)
    ])

    /// Laid out in a square centred on the pivot so that rotation needs no anchor maths:
    /// the arm runs along +x, the counterweight along -x.
    private var armAssembly: some View {
        ZStack {
            // The stub behind the pivot, and the counterweight on it.
            tube(length: counterweightLength, thickness: armLength * 0.024)
                .offset(x: -counterweightLength / 2)
            counterweight
                .offset(x: -counterweightLength * 0.86)

            // Main arm tube.
            tube(length: armLength * 0.88, thickness: armLength * 0.028)
                .offset(x: armLength * 0.44)

            headshell
                .offset(x: armLength * 0.93)
        }
        .frame(width: armLength * 2, height: armLength * 2)
        .shadow(color: .black.opacity(0.55), radius: armLength * 0.025, x: armLength * 0.008, y: armLength * 0.022)
    }

    private func tube(length: CGFloat, thickness: CGFloat) -> some View {
        Capsule()
            .fill(LinearGradient(gradient: Self.chrome, startPoint: .top, endPoint: .bottom))
            .frame(width: length, height: thickness)
    }

    /// A turned steel cylinder with grip rings, its flat face toward the pivot.
    private var counterweight: some View {
        let width = armLength * 0.16
        let height = armLength * 0.115
        let shape = RoundedRectangle(cornerRadius: height * 0.2, style: .continuous)
        return ZStack {
            shape.fill(LinearGradient(gradient: Self.chrome, startPoint: .top, endPoint: .bottom))
            HStack(spacing: width * 0.1) {
                ForEach(0..<5, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.black.opacity(0.3))
                        .frame(width: hairline)
                }
            }
            .padding(.vertical, height * 0.06)
            shape.strokeBorder(Color.black.opacity(0.4), lineWidth: hairline)
        }
        .frame(width: width, height: height)
    }

    private var headshell: some View {
        let shell = RoundedRectangle(cornerRadius: armLength * 0.016, style: .continuous)
        return ZStack {
            // Finger lift, angled off the side.
            Capsule()
                .fill(LinearGradient(gradient: Self.chrome, startPoint: .top, endPoint: .bottom))
                .frame(width: armLength * 0.10, height: armLength * 0.014)
                .rotationEffect(.degrees(-38))
                .offset(x: armLength * 0.035, y: -armLength * 0.055)

            // The shell: black anodised, its edge catching the light.
            shell
                .fill(LinearGradient(colors: [Color(white: 0.26), Color(white: 0.08)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: armLength * 0.17, height: armLength * 0.072)
            shell
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.4), .white.opacity(0.06)],
                                             startPoint: .top, endPoint: .bottom),
                              lineWidth: hairline)
                .frame(width: armLength * 0.17, height: armLength * 0.072)

            // The cartridge under the front of the shell — in the song's colour while
            // it plays — and the diamond at its tip.
            RoundedRectangle(cornerRadius: armLength * 0.008, style: .continuous)
                .fill(LinearGradient(colors: isEngaged ? [accent, accent.darkened(0.45)]
                                                       : [Color(white: 0.5), Color(white: 0.28)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: armLength * 0.075, height: armLength * 0.046)
                .offset(x: armLength * 0.035, y: armLength * 0.008)
            Circle()
                .fill(Color(white: 0.92))
                .frame(width: armLength * 0.014, height: armLength * 0.014)
                .offset(x: armLength * 0.068, y: armLength * 0.03)
        }
        .rotationEffect(.degrees(18))   // classic offset angle of the cartridge
    }

    /// The bearing the arm swings on: a machined base with a domed gimbal cap. It
    /// doesn't turn with the arm, so it's drawn on top, the arm running out from under it.
    private var pivotHousing: some View {
        let base = armLength * 0.22
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.52), Color(white: 0.24), Color(white: 0.44),
                                               Color(white: 0.20), Color(white: 0.50), Color(white: 0.26),
                                               Color(white: 0.52)],
                                      center: .center))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.5), .black.opacity(0.4)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: hairline * 1.5)
            Circle()
                .fill(RadialGradient(colors: [Color(white: 0.92), Color(white: 0.5), Color(white: 0.18)],
                                     center: UnitPoint(x: 0.35, y: 0.3),
                                     startRadius: 0,
                                     endRadius: base * 0.32))
                .frame(width: base * 0.56, height: base * 0.56)
                .shadow(color: .black.opacity(0.5), radius: base * 0.05, y: base * 0.03)
            Circle()
                .fill(Color(white: 0.1))
                .frame(width: base * 0.11, height: base * 0.11)
        }
        .frame(width: base, height: base)
        .shadow(color: .black.opacity(0.5), radius: armLength * 0.02, y: armLength * 0.012)
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
