import SwiftUI

/// A spinning 12" record with the cover art pressed into the centre label.
///
/// The disc splits into two layers: a static one (base, grooves) that never redraws, and
/// a rotating one (sheen, label, pressing mark). Concentric grooves look identical under
/// rotation, so keeping them still costs nothing visually.
///
/// The rotating part is drawn once into an image and spun by Core Animation: the
/// window server turns it at the display's own rate (120 Hz on ProMotion) while Spindle
/// does nothing per frame. It's redrawn only when the cover, colour or size changes.
struct VinylView: View {
    var artwork: NSImage?
    var accent: Color
    var isSpinning: Bool
    var rpm: Double = Theme.Record.rpm

    @State private var rotatingImage: CGImage?
    @Environment(\.displayScale) private var displayScale

    private var degreesPerSecond: Double { rpm * 6 }

    private struct RenderKey: Equatable {
        var size: CGFloat
        var artwork: ObjectIdentifier?
        var accent: Color
        var scale: CGFloat
    }

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                staticDisc(size: size)
                SpinningLayer(image: rotatingImage, isSpinning: isSpinning, degreesPerSecond: degreesPerSecond)
                    .frame(width: size, height: size)
            }
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: RenderKey(size: size, artwork: artwork.map(ObjectIdentifier.init),
                                accent: accent, scale: displayScale)) {
                guard size > 0 else { return }
                let renderer = ImageRenderer(content: rotatingDisc(size: size))
                renderer.scale = displayScale
                rotatingImage = renderer.cgImage
            }
        }
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

/// An image turned by Core Animation. Stopping freezes it where it is; starting again
/// carries on from there, the way a platter does.
struct SpinningLayer: NSViewRepresentable {
    var image: CGImage?
    var isSpinning: Bool
    var degreesPerSecond: Double

    func makeNSView(context: Context) -> SpinningLayerView { SpinningLayerView() }

    func updateNSView(_ view: SpinningLayerView, context: Context) {
        view.update(image: image, spinning: isSpinning, degreesPerSecond: degreesPerSecond)
    }
}

final class SpinningLayerView: NSView {
    private let disc = CALayer()
    private var isSpinning = false

    init() {
        super.init(frame: .zero)
        // Layer-hosting, so the disc's anchor stays at its centre whatever AppKit does.
        layer = CALayer()
        wantsLayer = true
        disc.contentsGravity = .resizeAspect
        layer?.addSublayer(disc)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.bounds = bounds
        disc.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func update(image: CGImage?, spinning: Bool, degreesPerSecond: Double) {
        if (disc.contents as! CGImage?) !== image {
            // A new cover cross-fades in (Core Animation's implicit fade on contents).
            disc.contents = image
        }
        guard spinning != isSpinning else { return }
        isSpinning = spinning
        let current = (disc.presentation() ?? disc).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        disc.removeAnimation(forKey: "spin")
        disc.setValue(current, forKeyPath: "transform.rotation.z")
        CATransaction.commit()
        guard spinning, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return }
        // Clockwise, seen from above: negative in Core Animation's y-up space.
        let spin = CABasicAnimation(keyPath: "transform.rotation.z")
        spin.fromValue = current
        spin.toValue = current - 2 * .pi
        spin.duration = 360 / max(degreesPerSecond, 1)
        spin.repeatCount = .infinity
        spin.isRemovedOnCompletion = false
        disc.add(spin, forKey: "spin")
    }
}
