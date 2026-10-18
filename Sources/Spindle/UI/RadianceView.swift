import AppKit
import SwiftUI

/// The "now playing" waves, after Vinylpod: a glow in the song's colour (or white, or a
/// colour of your choosing) that moves while music plays and settles when it's paused.
/// Small in the closed notch; larger beside the controls in the open panel. Three looks:
///
/// - Bars: rounded bars, tallest in the middle, like a waveform.
/// - Wave: one smooth line rippling across.
/// - Pulse: a dot that breathes.
///
/// Two kinds of motion:
/// - Decorative (default): layered sine waves, as Core Animation loops handed to the
///   window server once — Spindle does no work per frame. (Re-rendering it in SwiftUI
///   every frame cost a third of a CPU core.)
/// - Live ("React to the music"): the song's real sound, from `AudioLevels`, about 30
///   times a second.
struct RadianceView: View {
    enum Layout {
        /// In the closed notch's right wing.
        case notch
        /// Beside the controls in the open panel.
        case panel

        var size: CGSize { self == .notch ? CGSize(width: 36, height: 18) : CGSize(width: 96, height: 30) }
        var barCount: Int { self == .notch ? 5 : 11 }
        var barWidth: CGFloat { self == .notch ? 3 : 3.5 }
        var barSpacing: CGFloat { self == .notch ? 2.5 : 3.6 }
        var restHeight: CGFloat { self == .notch ? 3 : 3.5 }
        var peakHeight: CGFloat { self == .notch ? 15 : 27 }
    }

    var isPlaying: Bool
    var color: Color
    var style: NotchViewModel.IndicatorStyle = .bars
    /// 0.3 (soft) … 1 (bright).
    var brightness: Double = 0.85
    /// 0 (none) … 1 (strong halo).
    var glow: Double = 0.6
    var layout: Layout = .notch
    /// Move with the song's real sound rather than the decorative rhythm.
    var live = false

    var body: some View {
        RadianceLayers(isPlaying: isPlaying, color: NSColor(color), style: style,
                       brightness: brightness, glow: glow, layout: layout, live: live)
            .frame(width: layout.size.width, height: layout.size.height)
    }
}

private struct RadianceLayers: NSViewRepresentable {
    var isPlaying: Bool
    var color: NSColor
    var style: NotchViewModel.IndicatorStyle
    var brightness: Double
    var glow: Double
    var layout: RadianceView.Layout
    var live: Bool

    func makeNSView(context: Context) -> RadianceLayerView { RadianceLayerView(layout: layout) }

    func updateNSView(_ view: RadianceLayerView, context: Context) {
        view.update(isPlaying: isPlaying, color: color, style: style, brightness: brightness,
                    glow: glow, live: live)
    }
}

final class RadianceLayerView: NSView {
    private let placement: RadianceView.Layout
    private let root = CALayer()
    private let halo = CAGradientLayer()
    private var bars: [CAGradientLayer] = []
    private let waveHolder = CALayer()
    private let waveFill = CAGradientLayer()
    private let waveLine = CAShapeLayer()
    private let ring = CAShapeLayer()
    private let dot = CAGradientLayer()

    private var isPlaying = false
    private var style: NotchViewModel.IndicatorStyle?
    private var glow = 0.6
    private var wantsLive = false
    private var subscription: UUID?

    private var size: CGSize { placement.size }
    private var waveSize: CGSize { CGSize(width: size.width - 4, height: size.height - 2) }

    /// Tallest in the middle, tapering to the ends.
    private lazy var envelope: [Double] = (0..<placement.barCount).map { index in
        0.5 + 0.5 * pow(sin(Double.pi * (Double(index) + 0.5) / Double(placement.barCount)), 1.5)
    }

    init(layout: RadianceView.Layout) {
        self.placement = layout
        super.init(frame: CGRect(origin: .zero, size: layout.size))
        // Layer-hosting: the layers are ours to place and animate.
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(root)
        root.frame = CGRect(origin: .zero, size: size)
        // Top-down like SwiftUI, so gradients run light-at-the-top.
        root.isGeometryFlipped = true

        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        root.addSublayer(halo)

        let total = CGFloat(placement.barCount) * placement.barWidth + CGFloat(placement.barCount - 1) * placement.barSpacing
        for index in 0..<placement.barCount {
            let bar = CAGradientLayer()
            bar.cornerRadius = placement.barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: placement.barWidth, height: placement.restHeight)
            bar.position = CGPoint(x: (size.width - total) / 2 + CGFloat(index) * (placement.barWidth + placement.barSpacing)
                                      + placement.barWidth / 2,
                                   y: size.height / 2)
            bar.shadowOffset = .zero
            bar.shadowRadius = placement == .notch ? 3 : 4
            root.addSublayer(bar)
            bars.append(bar)
        }

        waveHolder.frame = CGRect(x: 2, y: 1, width: waveSize.width, height: waveSize.height)
        waveHolder.shadowOffset = .zero
        waveHolder.shadowRadius = 3
        waveFill.frame = waveHolder.bounds
        waveFill.startPoint = CGPoint(x: 0, y: 0.5)
        waveFill.endPoint = CGPoint(x: 1, y: 0.5)
        waveLine.frame = waveHolder.bounds
        waveLine.fillColor = nil
        waveLine.strokeColor = NSColor.white.cgColor
        waveLine.lineWidth = placement == .notch ? 2.2 : 2.6
        waveLine.lineCap = .round
        waveLine.lineJoin = .round
        waveFill.mask = waveLine
        waveHolder.addSublayer(waveFill)
        root.addSublayer(waveHolder)

        let ringSize: CGFloat = placement == .notch ? 8 : 13
        ring.bounds = CGRect(x: 0, y: 0, width: ringSize, height: ringSize)
        ring.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 1.5
        root.addSublayer(ring)

        let dotSize: CGFloat = placement == .notch ? 7 : 11
        dot.bounds = CGRect(x: 0, y: 0, width: dotSize, height: dotSize)
        dot.cornerRadius = dotSize / 2
        dot.position = ring.position
        dot.shadowOffset = .zero
        dot.shadowRadius = 4
        root.addSublayer(dot)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize { size }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [root, halo, waveHolder, waveFill, waveLine, ring, dot] + bars { layer.contentsScale = scale }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateSubscription()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Centred in whatever frame SwiftUI gives (it may be scaled up for a preview).
        root.position = CGPoint(x: bounds.midX, y: bounds.midY)
        root.bounds = CGRect(origin: .zero, size: size)
        CATransaction.commit()
    }

    func update(isPlaying: Bool, color: NSColor, style: NotchViewModel.IndicatorStyle,
                brightness: Double, glow: Double, live: Bool) {
        let color = color.usingColorSpace(.sRGB) ?? color
        let light = color.blended(withFraction: 0.25 + 0.35 * brightness, of: .white) ?? color
        root.opacity = Float(0.35 + 0.65 * brightness)

        halo.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
        let haloWidth = size.width * (style == .pulse ? 1.05 : 1.4)
        let haloHeight = size.height * 1.7
        halo.frame = CGRect(x: (size.width - haloWidth) / 2, y: (size.height - haloHeight) / 2,
                            width: haloWidth, height: haloHeight)
        for bar in bars {
            bar.colors = [light.cgColor, color.cgColor]
            bar.shadowColor = color.cgColor
        }
        waveFill.colors = [(color.blended(withFraction: 0.4 * brightness, of: .white) ?? color).cgColor, color.cgColor]
        waveHolder.shadowColor = color.cgColor
        ring.strokeColor = color.withAlphaComponent(0.5).cgColor
        dot.colors = [light.cgColor, color.cgColor]
        dot.shadowColor = color.cgColor

        let styleChanged = style != self.style
        let liveChanged = live != wantsLive
        let changed = styleChanged || liveChanged || isPlaying != self.isPlaying || glow != self.glow
        self.style = style
        self.glow = glow
        wantsLive = live
        guard changed else { return }
        let wasPlaying = self.isPlaying
        self.isPlaying = isPlaying

        for bar in bars { bar.isHidden = style != .bars }
        waveHolder.isHidden = style != .wave
        ring.isHidden = style != .pulse
        dot.isHidden = style != .pulse

        updateSubscription()
        let moving = isPlaying && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if moving && isLive {
            beginLive()
        } else if moving {
            startMotion(blendIn: !wasPlaying || styleChanged || liveChanged)
        } else {
            settle()
        }
    }

    // MARK: - Live

    /// Live only when asked for, playing, on screen, and macOS hasn't refused.
    private var isLive: Bool {
        wantsLive && isPlaying && window != nil && AudioLevels.shared.failure == nil
    }

    private func updateSubscription() {
        if isLive, subscription == nil {
            subscription = AudioLevels.shared.subscribe { [weak self] levels in self?.show(levels) }
            // The tap may have just failed to start (no permission): use the loops then.
            if AudioLevels.shared.failure != nil {
                AudioLevels.shared.unsubscribe(subscription)
                subscription = nil
                if isPlaying { startMotion(blendIn: true) }
            }
        } else if !isLive, let id = subscription {
            AudioLevels.shared.unsubscribe(id)
            subscription = nil
        }
    }

    private func beginLive() {
        for layer in [halo, ring, dot, waveLine] + bars as [CALayer] { layer.removeAllAnimations() }
        let shadow = Float(0.9 * glow)
        for bar in bars { bar.shadowOpacity = shadow }
        waveHolder.shadowOpacity = shadow
        dot.shadowOpacity = shadow
    }

    /// One frame of real levels: each bar takes the bands under it.
    private func show(_ bands: [Float]) {
        // macOS stopped sharing the sound: back to the usual rhythm.
        if AudioLevels.shared.failure != nil {
            updateSubscription()
            if isPlaying { startMotion(blendIn: true) }
            return
        }
        guard isLive else { return }
        let count = placement.barCount
        let values: [Double] = (0..<count).map { index in
            // Bass on the left, treble on the right, like a spectrum.
            let start = index * bands.count / count, end = max((index + 1) * bands.count / count, start + 1)
            let slice = bands[start..<min(end, bands.count)]
            return Double(slice.reduce(0, +)) / Double(slice.count)
        }
        let energy = values.reduce(0, +) / Double(max(values.count, 1))

        CATransaction.begin()
        CATransaction.setAnimationDuration(1.0 / 30.0)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear))
        halo.opacity = Float(glow * (0.3 + 0.6 * energy))
        switch style ?? .bars {
        case .bars:
            for (index, bar) in bars.enumerated() {
                let shaped = values[index] * (0.65 + 0.35 * envelope[index])
                bar.bounds.size.height = placement.restHeight + (placement.peakHeight - placement.restHeight) * CGFloat(shaped)
            }
        case .wave:
            let t = CACurrentMediaTime()
            waveLine.path = wavePath(t: t, amplitude: 0.05 + 0.4 * energy)
        case .pulse:
            let beat = min(values.first ?? 0, 1) * 0.6 + energy * 0.4
            ring.transform = CATransform3DMakeScale(1 + beat, 1 + beat, 1)
            ring.opacity = Float(1 - beat * 0.8)
            dot.transform = CATransform3DMakeScale(1 + beat * 0.15, 1 + beat * 0.15, 1)
        }
        CATransaction.commit()
    }

    // MARK: - Decorative motion

    /// One loop of each motion, sampled into keyframes. The frequencies are the
    /// originals nudged to whole multiples of the loop, so it repeats without a seam.
    private func startMotion(blendIn: Bool) {
        let glow = self.glow
        let shadow = Float(0.9 * glow)
        for bar in bars { bar.shadowOpacity = shadow }
        waveHolder.shadowOpacity = shadow
        dot.shadowOpacity = shadow
        dot.transform = CATransform3DIdentity

        // Halo: breathes with the music. Loop 8.4 s (ω 2.25 and 1.5).
        let haloLoop = 2 * Double.pi / 0.75
        loop(halo, "opacity", duration: haloLoop, samples: 48, blendIn: blendIn) { t in
            let energy = 0.5 + 0.5 * sin(t * 2.25) * sin(t * 1.5 + 1)
            return glow * (0.35 + 0.4 * energy)
        }

        switch style ?? .bars {
        case .bars:
            // Loop 4.65 s (ω 2.7, 5.4, 8.1 for the original 2.7, 5.1, 8.3).
            let barLoop = 2 * Double.pi * 20 / 27
            let rest = Double(placement.restHeight), span = Double(placement.peakHeight - placement.restHeight)
            for (index, bar) in bars.enumerated() {
                let phase = Double(index) * 1.3
                let envelope = self.envelope[index]
                loop(bar, "bounds.size.height", duration: barLoop, samples: 64, blendIn: blendIn) { t in
                    let wave = sin(t * 8.1 + phase * 1.9) * 0.35 + sin(t * 5.4 + phase) * 0.45 + sin(t * 2.7 + phase * 0.6) * 0.2
                    return rest + span * envelope * (0.35 + 0.65 * (wave + 1) / 2)
                }
            }
        case .wave:
            // Loop 2.09 s (ω 6 and 3).
            let waveLoop = 2 * Double.pi / 3
            let frames = (0..<40).map { wavePath(t: waveLoop * Double($0) / 40, amplitude: 0.36) }
            let animation = CAKeyframeAnimation(keyPath: "path")
            animation.values = frames + [frames[0]]
            animation.duration = waveLoop
            animation.repeatCount = .infinity
            animation.isRemovedOnCompletion = false
            waveLine.path = frames[0]
            waveLine.add(animation, forKey: "loop")
        case .pulse:
            // One beat every 1.5 s.
            let beatLoop = 2 * Double.pi / 4.2
            let beat: (Double) -> Double = { (sin($0 * 4.2) + 1) / 2 }
            loop(ring, "transform.scale", duration: beatLoop, samples: 32, blendIn: blendIn) { 1 + beat($0) }
            loop(ring, "opacity", duration: beatLoop, samples: 32, blendIn: blendIn) { 1 - beat($0) }
        }
    }

    /// Back to rest from wherever the motion is.
    private func settle() {
        let layers: [(CALayer, String, Double)] = [(halo, "opacity", 0), (ring, "transform.scale", 1), (ring, "opacity", 1)]
            + bars.map { ($0, "bounds.size.height", Double(placement.restHeight)) }
        for (layer, keyPath, rest) in layers {
            let from = layer.presentation()?.value(forKeyPath: keyPath) ?? rest
            layer.removeAllAnimations()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.setValue(rest, forKeyPath: keyPath)
            CATransaction.commit()
            let ease = CABasicAnimation(keyPath: keyPath)
            ease.fromValue = from
            ease.toValue = rest
            ease.duration = 0.35
            ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(ease, forKey: "settle")
        }
        waveLine.removeAllAnimations()
        waveLine.path = wavePath(t: 0, amplitude: 0.5 / 16)
        dot.transform = CATransform3DIdentity
        for layer in bars + [waveHolder, dot] as [CALayer] { layer.shadowOpacity = 0 }
    }

    /// A seamless looping keyframe animation of `keyPath`, eased in from the current
    /// value first so starting never jumps.
    private func loop(_ layer: CALayer, _ keyPath: String, duration: Double, samples: Int,
                      blendIn: Bool, value: (Double) -> Double) {
        let values = (0...samples).map { value(duration * Double($0) / Double(samples)) }
        layer.removeAllAnimations()
        let now = layer.convertTime(CACurrentMediaTime(), from: nil)
        let intro = blendIn ? 0.3 : 0
        if blendIn {
            let ease = CABasicAnimation(keyPath: keyPath)
            ease.fromValue = layer.presentation()?.value(forKeyPath: keyPath) ?? layer.value(forKeyPath: keyPath)
            ease.toValue = values[0]
            ease.duration = intro
            ease.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ease.fillMode = .forwards
            ease.isRemovedOnCompletion = false
            layer.add(ease, forKey: "intro")
        }
        let animation = CAKeyframeAnimation(keyPath: keyPath)
        animation.values = values
        animation.duration = duration
        animation.calculationMode = .cubic
        animation.repeatCount = .infinity
        animation.beginTime = now + intro
        animation.isRemovedOnCompletion = false
        layer.add(animation, forKey: "loop")
    }

    /// The rippling line, tapered at both ends so it fades out.
    private func wavePath(t: Double, amplitude: Double) -> CGPath {
        let path = CGMutablePath()
        let width = waveSize.width, height = waveSize.height
        let mid = height / 2
        let steps = placement == .notch ? 36 : 60
        let cycles = placement == .notch ? 1.0 : 1.8
        for step in 0...steps {
            let u = Double(step) / Double(steps)
            let taper = sin(u * .pi)
            let y = mid + CGFloat((sin(u * 9 * cycles - t * 6) * 0.65 + sin(u * 5 * cycles + t * 3) * 0.35)
                                  * amplitude * Double(height) * taper)
            let point = CGPoint(x: width * CGFloat(u), y: y)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }

    deinit {
        if let subscription {
            Task { @MainActor in AudioLevels.shared.unsubscribe(subscription) }
        }
    }
}

extension Color {
    /// Mixes toward white by `fraction` (0 = unchanged, 1 = white).
    func lightened(_ fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(nsColor: base.blended(withFraction: fraction, of: .white) ?? base)
    }
}
