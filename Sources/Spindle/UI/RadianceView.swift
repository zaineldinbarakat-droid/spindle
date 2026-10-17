import AppKit
import SwiftUI

/// The "now playing" mark in the collapsed notch, after Vinylpod: a glow in the song's
/// colour (or white, or a colour of your choosing) that moves while music plays and
/// settles when it's paused. Three looks:
///
/// - Bars: a few rounded bars, tallest in the middle, like a tiny waveform.
/// - Wave: one smooth line rippling across.
/// - Pulse: a single dot that breathes.
///
/// Decorative: the motion comes from layered sine waves rather than the audio itself,
/// which would need a system audio tap.
///
/// Drawn with Core Animation, not redrawn by SwiftUI: each motion is a looping keyframe
/// animation handed to the window server once, so while music plays Spindle itself does
/// no work per frame. (Re-rendering it every frame cost a third of a CPU core.)
struct RadianceView: View {
    var isPlaying: Bool
    var color: Color
    var style: NotchViewModel.IndicatorStyle = .bars
    /// 0.3 (soft) … 1 (bright).
    var brightness: Double = 0.85
    /// 0 (none) … 1 (strong halo).
    var glow: Double = 0.6

    var body: some View {
        RadianceLayers(isPlaying: isPlaying, color: NSColor(color), style: style,
                       brightness: brightness, glow: glow)
            .frame(width: 36, height: 18)
    }
}

private struct RadianceLayers: NSViewRepresentable {
    var isPlaying: Bool
    var color: NSColor
    var style: NotchViewModel.IndicatorStyle
    var brightness: Double
    var glow: Double

    func makeNSView(context: Context) -> RadianceLayerView { RadianceLayerView() }

    func updateNSView(_ view: RadianceLayerView, context: Context) {
        view.update(isPlaying: isPlaying, color: color, style: style, brightness: brightness, glow: glow)
    }
}

final class RadianceLayerView: NSView {
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

    private let size = CGSize(width: 36, height: 18)
    private let barCount = 5
    private let envelope: [Double] = [0.55, 0.82, 1.0, 0.82, 0.55]

    init() {
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: 36, height: 18)))
        // Layer-hosting: the layers are ours to place and animate.
        layer = CALayer()
        wantsLayer = true
        layer?.masksToBounds = false
        layer?.addSublayer(root)
        root.frame = CGRect(origin: .zero, size: size)
        // Top-down like SwiftUI, so gradients run light-at-the-top as before.
        root.isGeometryFlipped = true

        halo.type = .radial
        halo.startPoint = CGPoint(x: 0.5, y: 0.5)
        halo.endPoint = CGPoint(x: 1, y: 1)
        root.addSublayer(halo)

        let barWidth: CGFloat = 3, spacing: CGFloat = 2.5
        let total = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * spacing
        for index in 0..<barCount {
            let bar = CAGradientLayer()
            bar.cornerRadius = barWidth / 2
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: 3)
            bar.position = CGPoint(x: (size.width - total) / 2 + CGFloat(index) * (barWidth + spacing) + barWidth / 2,
                                   y: size.height / 2)
            bar.shadowOffset = .zero
            bar.shadowRadius = 3
            root.addSublayer(bar)
            bars.append(bar)
        }

        waveHolder.frame = CGRect(x: 2, y: 1, width: 32, height: 16)
        waveHolder.shadowOffset = .zero
        waveHolder.shadowRadius = 3
        waveFill.frame = waveHolder.bounds
        waveFill.startPoint = CGPoint(x: 0, y: 0.5)
        waveFill.endPoint = CGPoint(x: 1, y: 0.5)
        waveLine.frame = waveHolder.bounds
        waveLine.fillColor = nil
        waveLine.strokeColor = NSColor.white.cgColor
        waveLine.lineWidth = 2.2
        waveLine.lineCap = .round
        waveLine.lineJoin = .round
        waveFill.mask = waveLine
        waveHolder.addSublayer(waveFill)
        root.addSublayer(waveHolder)

        ring.bounds = CGRect(x: 0, y: 0, width: 8, height: 8)
        ring.position = CGPoint(x: size.width / 2, y: size.height / 2)
        ring.path = CGPath(ellipseIn: ring.bounds.insetBy(dx: 0.75, dy: 0.75), transform: nil)
        ring.fillColor = nil
        ring.lineWidth = 1.5
        root.addSublayer(ring)

        dot.bounds = CGRect(x: 0, y: 0, width: 7, height: 7)
        dot.cornerRadius = 3.5
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
                brightness: Double, glow: Double) {
        let color = color.usingColorSpace(.sRGB) ?? color
        let light = color.blended(withFraction: 0.25 + 0.35 * brightness, of: .white) ?? color
        root.opacity = Float(0.35 + 0.65 * brightness)

        halo.colors = [color.cgColor, color.withAlphaComponent(0).cgColor]
        let haloWidth: CGFloat = style == .pulse ? 38 : 50
        halo.frame = CGRect(x: (size.width - haloWidth) / 2, y: (size.height - 30) / 2, width: haloWidth, height: 30)
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
        let changed = styleChanged || isPlaying != self.isPlaying || glow != self.glow
        self.style = style
        self.glow = glow
        guard changed else { return }
        let wasPlaying = self.isPlaying
        self.isPlaying = isPlaying

        for bar in bars { bar.isHidden = style != .bars }
        waveHolder.isHidden = style != .wave
        ring.isHidden = style != .pulse
        dot.isHidden = style != .pulse

        let moving = isPlaying && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if moving {
            startMotion(blendIn: !wasPlaying || styleChanged)
        } else {
            settle()
        }
    }

    // MARK: - Motion

    /// One loop of each motion, sampled into keyframes. The frequencies are the
    /// originals nudged to whole multiples of the loop, so it repeats without a seam.
    private func startMotion(blendIn: Bool) {
        let glow = self.glow
        let shadow = Float(0.9 * glow)
        for bar in bars { bar.shadowOpacity = shadow }
        waveHolder.shadowOpacity = shadow
        dot.shadowOpacity = shadow

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
            for (index, bar) in bars.enumerated() {
                let phase = Double(index) * 1.3
                let envelope = self.envelope[index]
                loop(bar, "bounds.size.height", duration: barLoop, samples: 64, blendIn: blendIn) { t in
                    let wave = sin(t * 8.1 + phase * 1.9) * 0.35 + sin(t * 5.4 + phase) * 0.45 + sin(t * 2.7 + phase * 0.6) * 0.2
                    return 3 + 12 * envelope * (0.35 + 0.65 * (wave + 1) / 2)
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

    /// Back to rest from wherever the motion is, the way the SwiftUI version eased out.
    private func settle() {
        let layers: [(CALayer, String, Double)] = [(halo, "opacity", 0), (ring, "transform.scale", 1), (ring, "opacity", 1)]
            + bars.map { ($0, "bounds.size.height", 3) }
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
        for layer in bars + [waveHolder, dot] as [CALayer] { layer.shadowOpacity = 0 }
    }

    /// A seamless looping keyframe animation of `keyPath`, optionally eased in from the
    /// current value first so starting never jumps.
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

    /// The rippling line, tapered at both ends so it fades into the notch.
    private func wavePath(t: Double, amplitude: Double) -> CGPath {
        let path = CGMutablePath()
        let width: CGFloat = 32, height: CGFloat = 16
        let mid = height / 2
        for step in 0...36 {
            let u = Double(step) / 36
            let taper = sin(u * .pi)
            let y = mid + CGFloat((sin(u * 9 - t * 6) * 0.65 + sin(u * 5 + t * 3) * 0.35) * amplitude * Double(height) * taper)
            let point = CGPoint(x: width * CGFloat(u), y: y)
            step == 0 ? path.move(to: point) : path.addLine(to: point)
        }
        return path
    }
}

extension Color {
    /// Mixes toward white by `fraction` (0 = unchanged, 1 = white).
    func lightened(_ fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(nsColor: base.blended(withFraction: fraction, of: .white) ?? base)
    }
}
