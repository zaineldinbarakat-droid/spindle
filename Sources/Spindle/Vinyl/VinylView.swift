import SwiftUI

/// A spinning 12" record with the cover art pressed into the centre label.
///
/// Drawn the way a record looks under a lamp: deep black vinyl whose fine grooves catch
/// the light in two opposed wedges, smooth bands between the tracks, a glossy lead-in
/// and run-out, and a bevelled rim. The lamp doesn't turn with the record, so neither do
/// the grooves' highlights: the whole surface is one static layer that never redraws.
/// Only the label and a small etching in the run-out turn, and a steel spindle sits
/// still through the middle.
///
/// The turning part is drawn once into an image and spun by Core Animation: the
/// window server turns it at the display's own rate (120 Hz on ProMotion) while Spindle
/// does nothing per frame. It's redrawn only when the cover, colour or size changes.
struct VinylView: View {
    var artwork: NSImage?
    var accent: Color
    var isSpinning: Bool
    /// Overrides the speed chosen in Settings → Record.
    var rpm: Double?

    @State private var rotatingImage: CGImage?
    @Environment(\.displayScale) private var displayScale
    /// Settings → Record. AppStorage, so every record (notch, widgets, wallpaper) follows.
    @AppStorage(Defaults.Key.showsSpindlePin.rawValue) private var showsPin = true
    @AppStorage(Defaults.Key.recordLabelSize.rawValue) private var labelSize = Double(Theme.Record.labelFraction)
    @AppStorage(Defaults.Key.recordRPM.rawValue) private var storedRPM = Theme.Record.rpm
    /// Off: the album art holds still while the record turns under it.
    @AppStorage(Defaults.Key.labelSpins.rawValue) private var labelSpins = true
    /// The lamp's reflection sways once a turn, the way it does on a real (never quite
    /// flat) record, so the spin shows on the vinyl itself: perfect grooves look still.
    @AppStorage(Defaults.Key.showsSpin.rawValue) private var showsSpin = false

    private var degreesPerSecond: Double { (rpm ?? storedRPM) * 6 }
    private var labelFraction: CGFloat {
        CGFloat(min(max(labelSize, Theme.Record.labelFractionRange.lowerBound), Theme.Record.labelFractionRange.upperBound))
    }

    private struct RenderKey: Equatable {
        var size: CGFloat
        var artwork: ObjectIdentifier?
        var accent: Color
        var scale: CGFloat
        var labelFraction: CGFloat
        var labelSpins: Bool
        var showsSpin: Bool
    }

    @State private var lightImage: CGImage?

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)

            ZStack {
                // Showing the spin, the lamp's reflection is its own layer so it can sway
                // the way it does on a real (never perfectly flat) record.
                VinylSurface(labelFraction: labelFraction, includesLight: !showsSpin)
                    .frame(width: size, height: size)
                    .drawingGroup()
                if showsSpin {
                    SwayingLayer(image: lightImage, isSwaying: isSpinning, period: 360 / max(degreesPerSecond, 1))
                        .frame(width: size, height: size)
                }
                SpinningLayer(image: rotatingImage, isSpinning: isSpinning, degreesPerSecond: degreesPerSecond)
                    .frame(width: size, height: size)
                if !labelSpins {
                    label(size: size)
                }
                if showsPin {
                    spindle(size: size)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.2), value: showsPin)
            .frame(width: size, height: size)
            .frame(width: geo.size.width, height: geo.size.height)
            .task(id: RenderKey(size: size, artwork: artwork.map(ObjectIdentifier.init),
                                accent: accent, scale: displayScale, labelFraction: labelFraction,
                                labelSpins: labelSpins, showsSpin: showsSpin)) {
                guard size > 0 else { return }
                let renderer = ImageRenderer(content: rotatingDisc(size: size))
                renderer.scale = displayScale
                rotatingImage = renderer.cgImage
                if showsSpin {
                    let light = ImageRenderer(content: VinylLight(labelFraction: labelFraction)
                        .frame(width: size, height: size))
                    light.scale = displayScale
                    lightImage = light.cgImage
                } else {
                    lightImage = nil
                }
            }
        }
    }

    // MARK: - The turning part

    private func rotatingDisc(size: CGFloat) -> some View {
        ZStack {
            matrixEtching(size: size)
            if labelSpins {
                label(size: size)
            }
        }
        .frame(width: size, height: size)
    }

    /// The pressing plant's hand-scratched mark in the run-out: a short arc that shows
    /// the record turning even though its grooves look the same at every angle.
    private func matrixEtching(size: CGFloat) -> some View {
        let zones = VinylZones(radius: size / 2, labelFraction: labelFraction)
        let radius = (zones.labelEdge + zones.runOut) / 2
        return Path { path in
            path.addArc(center: CGPoint(x: size / 2, y: size / 2), radius: radius,
                        startAngle: .degrees(-118), endAngle: .degrees(-62), clockwise: false)
        }
        .stroke(Color.white.opacity(0.16), style: StrokeStyle(lineWidth: max(size * 0.004, 0.4),
                                                              lineCap: .round, dash: [size * 0.012, size * 0.006]))
        .frame(width: size, height: size)
    }

    private func label(size: CGFloat) -> some View {
        let labelSize = size * labelFraction

        return ZStack {
            Circle()
                .fill(
                    LinearGradient(colors: [accent.opacity(0.95), accent.opacity(0.7)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .frame(width: labelSize, height: labelSize)
                    .clipShape(Circle())
                    .transition(.opacity)
            }

            // Printed paper, not a sticker: a soft falloff toward the edge, the faint ring
            // labels are printed with, and the dark seam where the vinyl was pressed on.
            Circle()
                .fill(
                    RadialGradient(colors: [.clear, .black.opacity(0.32)],
                                   center: .center,
                                   startRadius: labelSize * 0.28,
                                   endRadius: labelSize * 0.52)
                )
            Circle()
                .strokeBorder(Color.white.opacity(0.10), lineWidth: max(labelSize * 0.006, 0.3))
                .padding(labelSize * 0.07)
            Circle()
                .strokeBorder(Color.black.opacity(0.55), lineWidth: max(labelSize * 0.022, 0.5))
        }
        .frame(width: labelSize, height: labelSize)
        .animation(.easeOut(duration: 0.35), value: artwork)
    }

    // MARK: - Still parts on top

    /// The turntable's steel spindle through the label hole: it doesn't turn with the
    /// record, so its highlight stays put.
    private func spindle(size: CGFloat) -> some View {
        let pin = max(size * Theme.Record.spindleFraction, 1.5)
        let hairline = max(pin * 0.06, 0.25)
        return ZStack {
            // The punched hole round the pin, its far edge catching a little light.
            Circle()
                .fill(Color.black.opacity(0.78))
                .frame(width: pin * 1.5, height: pin * 1.5)
            Circle()
                .strokeBorder(LinearGradient(colors: [.black.opacity(0.6), .white.opacity(0.22)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: hairline * 1.4)
                .frame(width: pin * 1.5, height: pin * 1.5)
            // Turned steel: faint rings from the lathe, a domed top lit from the upper
            // left, and a crisp edge.
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.84), Color(white: 0.48), Color(white: 0.72),
                                               Color(white: 0.42), Color(white: 0.84)],
                                      center: .center))
                .frame(width: pin, height: pin)
            Circle()
                .fill(RadialGradient(colors: [.white.opacity(0.95), .white.opacity(0)],
                                     center: UnitPoint(x: 0.34, y: 0.3),
                                     startRadius: 0,
                                     endRadius: pin * 0.45))
                .frame(width: pin, height: pin)
            Circle()
                .strokeBorder(Color.black.opacity(0.5), lineWidth: hairline)
                .frame(width: pin, height: pin)
        }
        .shadow(color: .black.opacity(0.6), radius: pin * 0.16, x: pin * 0.06, y: pin * 0.1)
        .allowsHitTesting(false)
    }
}

/// The record's surface, lit from the upper left: everything on a record that doesn't
/// turn visibly when it plays. Without `includesLight`, just the vinyl: `VinylLight`
/// then draws the lamp's reflection as a layer of its own.
private struct VinylSurface: View {
    var labelFraction: CGFloat
    var includesLight = true

    var body: some View {
        Canvas { context, canvas in
            let size = min(canvas.width, canvas.height)
            let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
            let radius = size / 2
            let zones = VinylZones(radius: radius, labelFraction: labelFraction)

            func circle(_ r: CGFloat) -> Path {
                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            }
            func band(_ inner: CGFloat, _ outer: CGFloat) -> Path {
                var path = circle(outer)
                path.addPath(circle(inner))
                return path
            }
            let eoFill = FillStyle(eoFill: true)
            let disc = circle(radius)

            // The vinyl: black, a breath lighter toward the middle where it's thickest.
            context.fill(disc, with: .radialGradient(
                Gradient(colors: [Color(white: 0.085), Color(white: 0.05), Color(white: 0.032)]),
                center: center, startRadius: 0, endRadius: radius))

            // Grooves: a fine, uneven texture, the way the cut varies with the music.
            let grooves = zones.grooves(size: size)
            let hairline = max(size * 0.0018, 0.3)
            for groove in grooves {
                context.stroke(circle(groove.radius),
                               with: .color(.white.opacity(groove.texture)),
                               lineWidth: groove.isLeadIn ? hairline * 1.8 : hairline)
            }

            // The smooth bands — between tracks, the run-out, the rim — are glossier
            // and a touch darker than the grooved vinyl around them.
            for gap in zones.trackGaps {
                context.fill(band(gap.lowerBound, gap.upperBound), with: .color(.black.opacity(0.55)), style: eoFill)
                context.stroke(circle(gap.upperBound), with: .color(.white.opacity(0.07)), lineWidth: hairline)
            }
            context.fill(band(zones.labelEdge, zones.runOut), with: .color(.black.opacity(0.35)), style: eoFill)
            for locked in zones.lockedGrooves {
                context.stroke(circle(locked), with: .color(.white.opacity(0.10)), lineWidth: hairline)
            }

            if includesLight {
                Self.drawLight(in: &context, size: size, center: center, grooves: grooves)
            }

            // The rim: rounded over, so it catches the light on the lamp's side and
            // falls into shadow on the other.
            let bevel = max(size * 0.009, 0.6)
            context.stroke(circle(radius - bevel / 2),
                           with: .linearGradient(Gradient(colors: [.white.opacity(0.30), .white.opacity(0.03)]),
                                                 startPoint: CGPoint(x: center.x - radius, y: center.y - radius),
                                                 endPoint: CGPoint(x: center.x + radius, y: center.y + radius)),
                           lineWidth: bevel)
            context.stroke(circle(radius - bevel * 1.5), with: .color(.black.opacity(0.6)), lineWidth: bevel * 0.6)
        }
    }

    /// The lamp: two opposed wedges of light that only the grooves pick up, as streaks
    /// along them (brighter toward the light, upper left), and a broad, soft gloss.
    static func drawLight(in context: inout GraphicsContext, size: CGFloat, center: CGPoint,
                          grooves: [VinylZones.Groove]) {
        let radius = size / 2
        func circle(_ r: CGFloat) -> Path {
            Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
        }
        let disc = circle(radius)
        let hairline = max(size * 0.0018, 0.3)
        let light = Gradient(stops: [
            .init(color: .white.opacity(1.00), location: 0.000),
            .init(color: .white.opacity(0.42), location: 0.025),
            .init(color: .white.opacity(0.00), location: 0.080),
            .init(color: .white.opacity(0.00), location: 0.420),
            .init(color: .white.opacity(0.24), location: 0.475),
            .init(color: .white.opacity(0.62), location: 0.500),
            .init(color: .white.opacity(0.24), location: 0.525),
            .init(color: .white.opacity(0.00), location: 0.580),
            .init(color: .white.opacity(0.00), location: 0.920),
            .init(color: .white.opacity(0.42), location: 0.975),
            .init(color: .white.opacity(1.00), location: 1.000)
        ])
        let lampAngle = Angle.degrees(225) // pointing up and to the left, on screen
        context.drawLayer { layer in
            for groove in grooves {
                layer.stroke(circle(groove.radius), with: .color(.white.opacity(0.55 + groove.texture * 4)),
                             lineWidth: hairline * 1.2)
            }
            layer.blendMode = .sourceIn
            layer.fill(disc, with: .conicGradient(light, center: center, angle: lampAngle))
        }

        // The gloss on top: the same light as a broad, soft sheen over the whole disc.
        let gloss = Gradient(stops: [
            .init(color: .white.opacity(0.09), location: 0.00),
            .init(color: .white.opacity(0.00), location: 0.12),
            .init(color: .white.opacity(0.00), location: 0.38),
            .init(color: .white.opacity(0.05), location: 0.50),
            .init(color: .white.opacity(0.00), location: 0.62),
            .init(color: .white.opacity(0.00), location: 0.88),
            .init(color: .white.opacity(0.09), location: 1.00)
        ])
        context.fill(disc, with: .conicGradient(gloss, center: center, angle: lampAngle))
    }
}

/// The lamp's reflection on its own, for `SwayingLayer` to move.
private struct VinylLight: View {
    var labelFraction: CGFloat

    var body: some View {
        Canvas { context, canvas in
            let size = min(canvas.width, canvas.height)
            let zones = VinylZones(radius: size / 2, labelFraction: labelFraction)
            VinylSurface.drawLight(in: &context, size: size,
                                   center: CGPoint(x: canvas.width / 2, y: canvas.height / 2),
                                   grooves: zones.grooves(size: size))
        }
    }
}

/// Where everything sits on the record, as radii.
private struct VinylZones {
    var radius: CGFloat
    /// The label's diameter as a share of the record's.
    var labelFraction: CGFloat

    struct Groove {
        var radius: CGFloat
        /// How much this groove catches stray light, 0...~0.07: the texture of the cut.
        var texture: Double
        var isLeadIn: Bool
    }

    var labelEdge: CGFloat { radius * labelFraction }
    /// Where the music ends and the smooth run-out begins: just past the label, so a
    /// bigger label pushes the grooves out rather than covering them.
    var runOut: CGFloat { radius * max(Theme.Record.grooveInnerFraction, labelFraction + 0.045) }
    /// Where the music starts, inside the coarser lead-in.
    var leadIn: CGFloat { radius * (Theme.Record.grooveOuterFraction - 0.03) }
    var outerGroove: CGFloat { radius * Theme.Record.grooveOuterFraction }

    /// The silent bands between tracks, at fixed spots so every record looks pressed
    /// from the same master.
    var trackGaps: [ClosedRange<CGFloat>] {
        let width = radius * 0.009
        return [0.14, 0.31, 0.49, 0.64, 0.81].map { t in
            let r = runOut + (leadIn - runOut) * t
            return (r - width / 2)...(r + width / 2)
        }
    }

    /// The locked groove and its neighbour, where the stylus ends up circling.
    var lockedGrooves: [CGFloat] {
        [runOut - radius * 0.008, labelEdge + radius * 0.012]
    }

    func grooves(size: CGFloat) -> [Groove] {
        let pitch = max(size * 0.0042, 0.55)
        let gaps = trackGaps
        var result: [Groove] = []
        var r = runOut
        var index = 0
        while r < outerGroove {
            defer { r += r > leadIn ? pitch * 2.6 : pitch; index += 1 }
            if gaps.contains(where: { $0.contains(r) }) { continue }
            // A cheap, repeatable "random" texture: loud passages cut wider grooves.
            let wobble = (sin(Double(index) * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let swell = 0.5 + 0.5 * sin(Double(r / radius) * 41)
            result.append(Groove(radius: r,
                                 texture: 0.022 + 0.03 * abs(wobble) + 0.018 * swell,
                                 isLeadIn: r > leadIn))
        }
        return result
    }
}

/// The lamp's reflection on a record that isn't perfectly flat — none is: as the record
/// turns, the reflection sways a few degrees and dims a little as the warp tips it
/// away, once per turn. That, not the light turning with the record, is how a real
/// one gives its spin away. Core Animation does the moving.
struct SwayingLayer: NSViewRepresentable {
    var image: CGImage?
    var isSwaying: Bool
    /// One turn of the record, in seconds.
    var period: Double

    func makeNSView(context: Context) -> SwayingLayerView { SwayingLayerView() }

    func updateNSView(_ view: SwayingLayerView, context: Context) {
        view.update(image: image, swaying: isSwaying, period: period)
    }
}

final class SwayingLayerView: NSView {
    private let light = CALayer()
    private var isSwaying = false
    private var period: Double = 0

    init() {
        super.init(frame: .zero)
        layer = CALayer()
        wantsLayer = true
        light.contentsGravity = .resizeAspect
        layer?.addSublayer(light)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        light.bounds = bounds
        light.position = CGPoint(x: bounds.midX, y: bounds.midY)
        CATransaction.commit()
    }

    func update(image: CGImage?, swaying: Bool, period: Double) {
        if (light.contents as! CGImage?) !== image {
            light.contents = image
        }
        guard swaying != isSwaying || (swaying && period != self.period) else { return }
        isSwaying = swaying
        self.period = period

        let current = (light.presentation() ?? light).value(forKeyPath: "transform.rotation.z") as? CGFloat ?? 0
        light.removeAllAnimations()
        guard swaying, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            // Settle back where the light rests, rather than snapping.
            let settle = CABasicAnimation(keyPath: "transform.rotation.z")
            settle.fromValue = current
            settle.toValue = 0
            settle.duration = 0.5
            settle.timingFunction = CAMediaTimingFunction(name: .easeOut)
            light.add(settle, forKey: "settle")
            return
        }

        let ease = CAMediaTimingFunction(name: .easeInEaseOut)
        let amount = 3 * Double.pi / 180
        let sway = CAKeyframeAnimation(keyPath: "transform.rotation.z")
        sway.values = [0, amount, 0, -amount, 0]
        sway.keyTimes = [0, 0.25, 0.5, 0.75, 1]
        sway.timingFunctions = Array(repeating: ease, count: 4)
        sway.duration = period
        sway.repeatCount = .infinity
        light.add(sway, forKey: "sway")

        let dim = CAKeyframeAnimation(keyPath: "opacity")
        dim.values = [1, 0.8, 1]
        dim.keyTimes = [0, 0.5, 1]
        dim.timingFunctions = [ease, ease]
        dim.duration = period
        dim.timeOffset = period * 0.25   // dimmest as it sways furthest one way
        dim.repeatCount = .infinity
        light.add(dim, forKey: "dim")
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
    private var degreesPerSecond: Double = 0

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
        // A new speed restarts the spin from wherever the record is, like a turntable's
        // speed switch.
        guard spinning != isSpinning || (spinning && degreesPerSecond != self.degreesPerSecond) else { return }
        isSpinning = spinning
        self.degreesPerSecond = degreesPerSecond
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
