import SwiftUI

/// The "now playing" mark in the collapsed notch, after Vinylpod: a glow in the song's
/// colour (or white, or a colour of your choosing) that moves while music plays and
/// settles when it's paused. Three looks:
///
/// - Bars: a few rounded bars, tallest in the middle, like a tiny waveform.
/// - Wave: one smooth line rippling across.
/// - Pulse: a single dot that breathes.
///
/// Decorative, like `VisualizerView`: the motion comes from layered sine waves rather
/// than the audio itself, which would need a system audio tap.
struct RadianceView: View {
    var isPlaying: Bool
    var color: Color
    var style: NotchViewModel.IndicatorStyle = .bars
    /// 0.3 (soft) … 1 (bright).
    var brightness: Double = 0.85
    /// 0 (none) … 1 (strong halo).
    var glow: Double = 0.6

    private let barCount = 5
    private let envelope: [Double] = [0.55, 0.82, 1.0, 0.82, 0.55]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let energy = isPlaying ? 0.5 + 0.5 * sin(t * 2.3) * sin(t * 1.7 + 1) : 0

            ZStack {
                // Halo behind everything, breathing with the music.
                Capsule()
                    .fill(color)
                    .frame(width: style == .pulse ? 22 : 34, height: 16)
                    .blur(radius: 8)
                    .opacity(isPlaying ? glow * (0.35 + 0.4 * energy) : 0)

                switch style {
                case .bars: bars(t)
                case .wave: wave(t)
                case .pulse: pulse(t)
                }
            }
            .opacity(0.35 + 0.65 * brightness)
            .animation(.easeOut(duration: 0.35), value: isPlaying)
        }
        .frame(width: 36, height: 18)
    }

    private var fill: LinearGradient {
        LinearGradient(colors: [color.lightened(0.25 + 0.35 * brightness), color],
                       startPoint: .top, endPoint: .bottom)
    }

    private func bars(_ t: TimeInterval) -> some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule()
                    .fill(fill)
                    .frame(width: 3, height: 3 + 12 * level(index, t))
                    .shadow(color: color.opacity(isPlaying ? 0.9 * glow : 0), radius: 3)
            }
        }
    }

    private func wave(_ t: TimeInterval) -> some View {
        Canvas { context, size in
            var path = Path()
            let mid = size.height / 2
            let amplitude = isPlaying ? size.height * 0.36 : 0.5
            for step in 0...36 {
                let x = size.width * CGFloat(step) / 36
                let u = Double(step) / 36
                // Taper at both ends so the line fades into the notch.
                let taper = sin(u * .pi)
                let y = mid + CGFloat(sin(u * 9 - t * 6) * 0.65 + sin(u * 5 + t * 3.1) * 0.35) * amplitude * taper
                step == 0 ? path.move(to: CGPoint(x: x, y: y)) : path.addLine(to: CGPoint(x: x, y: y))
            }
            context.stroke(path, with: .linearGradient(Gradient(colors: [color.lightened(0.4 * brightness), color]),
                                                         startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)),
                           style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 32, height: 16)
        .shadow(color: color.opacity(isPlaying ? 0.9 * glow : 0), radius: 3)
    }

    private func pulse(_ t: TimeInterval) -> some View {
        let beat = isPlaying ? (sin(t * 4.2) + 1) / 2 : 0
        return ZStack {
            Circle().stroke(color.opacity(0.5 * (1 - beat)), lineWidth: 1.5)
                .frame(width: 8 + 8 * beat, height: 8 + 8 * beat)
            Circle().fill(fill).frame(width: 7, height: 7)
                .shadow(color: color.opacity(isPlaying ? 0.9 * glow : 0), radius: 4)
        }
    }

    private func level(_ index: Int, _ time: TimeInterval) -> Double {
        guard isPlaying else { return 0 }
        let phase = Double(index) * 1.3
        let wave = sin(time * 5.1 + phase) * 0.45
            + sin(time * 8.3 + phase * 1.9) * 0.35
            + sin(time * 2.7 + phase * 0.6) * 0.2
        return envelope[index] * (0.35 + 0.65 * (wave + 1) / 2)
    }
}

extension Color {
    /// Mixes toward white by `fraction` (0 = unchanged, 1 = white).
    func lightened(_ fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .white
        return Color(nsColor: base.blended(withFraction: fraction, of: .white) ?? base)
    }
}
