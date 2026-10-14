import SwiftUI

/// A spinning 12" record with the cover art pressed into the centre label.
///
/// The disc splits into two layers: a static one (base, grooves) that never redraws, and
/// a rotating one (sheen, label, pressing mark). Concentric grooves look identical under
/// rotation, so keeping them still costs nothing visually and saves a full Canvas redraw
/// on every frame.
struct VinylView: View {
    var artwork: NSImage?
    var accent: Color
    var isSpinning: Bool
    var rpm: Double = Theme.Record.rpm

    @State private var baseAngle: Double = 0
    @State private var spinStart: Date?

    private var degreesPerSecond: Double { rpm * 6 }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            TimelineView(.animation(minimumInterval: 1.0 / 90.0, paused: !isSpinning)) { timeline in
                ZStack {
                    staticDisc(size: size)
                    rotatingDisc(size: size)
                        .rotationEffect(.degrees(angle(at: timeline.date)))
                }
                .frame(width: size, height: size)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .onAppear { if isSpinning { spinStart = .now } }
        .onChange(of: isSpinning) { _, nowSpinning in
            let now = Date.now
            if nowSpinning {
                spinStart = now
            } else if let start = spinStart {
                // Freeze where the record actually is rather than snapping to zero.
                baseAngle = normalized(baseAngle + now.timeIntervalSince(start) * degreesPerSecond)
                spinStart = nil
            }
        }
    }

    private func angle(at date: Date) -> Double {
        guard let spinStart else { return baseAngle }
        return baseAngle + date.timeIntervalSince(spinStart) * degreesPerSecond
    }

    private func normalized(_ degrees: Double) -> Double {
        degrees.truncatingRemainder(dividingBy: 360)
    }

    // MARK: - Layers

    private func staticDisc(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color(white: 0.16), Color(white: 0.07), Color(white: 0.03)],
                        center: .center,
                        startRadius: size * 0.1,
                        endRadius: size * 0.5
                    )
                )

            GrooveCanvas(accent: accent)

            // Lip at the very edge where the pressing thickens.
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: max(size * 0.006, 0.5))
        }
        .frame(width: size, height: size)
        .drawingGroup()
    }

    private func rotatingDisc(size: CGFloat) -> some View {
        ZStack {
            sheen(size: size)
            pressingMark(size: size)
            label(size: size)
            spindleHole(size: size)
        }
        .frame(width: size, height: size)
    }

    /// Two opposed highlights sweeping the disc — what sells it as a glossy surface.
    private func sheen(size: CGFloat) -> some View {
        Circle()
            .fill(
                AngularGradient(
                    gradient: Gradient(stops: [
                        .init(color: .white.opacity(0.00), location: 0.00),
                        .init(color: .white.opacity(0.11), location: 0.10),
                        .init(color: .white.opacity(0.00), location: 0.22),
                        .init(color: .white.opacity(0.00), location: 0.48),
                        .init(color: .white.opacity(0.09), location: 0.60),
                        .init(color: .white.opacity(0.00), location: 0.72),
                        .init(color: .white.opacity(0.00), location: 1.00)
                    ]),
                    center: .center
                )
            )
            .blendMode(.screen)
            .frame(width: size, height: size)
    }

    private func pressingMark(size: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.05))
            .frame(width: max(size * 0.0035, 0.5),
                   height: size * (Theme.Record.grooveOuterFraction - Theme.Record.grooveInnerFraction) / 2)
            .offset(y: -size * (Theme.Record.grooveOuterFraction + Theme.Record.grooveInnerFraction) / 4)
    }

    private func label(size: CGFloat) -> some View {
        let labelSize = size * Theme.Record.labelFraction

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: labelSize, height: labelSize)
                    .clipShape(Circle())
                    .transition(.opacity)
            }

            // Paper texture ring so the art reads as a printed label, not a sticker.
            Circle()
                .strokeBorder(Color.black.opacity(0.35), lineWidth: labelSize * 0.03)

            Circle()
                .fill(
                    RadialGradient(colors: [.clear, .black.opacity(0.35)],
                                   center: .center,
                                   startRadius: labelSize * 0.25,
                                   endRadius: labelSize * 0.52)
                )
        }
        .frame(width: labelSize, height: labelSize)
        .animation(.easeOut(duration: 0.35), value: artwork)
    }

    private func spindleHole(size: CGFloat) -> some View {
        let hole = size * Theme.Record.spindleFraction
        return Circle()
            .fill(Color(white: 0.05))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.8), lineWidth: 0.5))
            .frame(width: hole, height: hole)
            .shadow(color: .black.opacity(0.6), radius: hole * 0.2)
    }
}

/// Concentric grooves, plus the wider spacing of the lead-in and run-out bands.
private struct GrooveCanvas: View {
    var accent: Color

    var body: some View {
        Canvas { context, size in
            let dimension = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let outer = dimension / 2 * Theme.Record.grooveOuterFraction
            let inner = dimension / 2 * Theme.Record.grooveInnerFraction

            let count = max(Int(dimension / 3.0), 24)
            let lineWidth = max(dimension * 0.0022, 0.35)

            for index in 0..<count {
                let t = Double(index) / Double(count - 1)
                let radius = outer - (outer - inner) * t

                // Lead-in and run-out grooves are cut coarser than the audio band.
                let isBand = t < 0.06 || t > 0.94
                let opacity = isBand ? 0.20 : 0.055 + 0.045 * sin(t * .pi * 9)

                let rect = CGRect(x: center.x - radius, y: center.y - radius,
                                  width: radius * 2, height: radius * 2)
                context.stroke(Path(ellipseIn: rect),
                               with: .color(.white.opacity(opacity)),
                               lineWidth: isBand ? lineWidth * 1.6 : lineWidth)
            }
        }
    }
}
