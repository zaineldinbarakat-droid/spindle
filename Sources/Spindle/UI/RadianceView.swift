import SwiftUI

/// The "now playing" mark in the collapsed notch: a few glowing bars in the cover's
/// colour, tallest in the middle, over a soft halo that breathes with them. Paused,
/// they sink to dots and the glow fades.
///
/// Decorative, like `VisualizerView`: the motion comes from layered sine waves rather
/// than the audio itself, which would need a system audio tap.
struct RadianceView: View {
    var isPlaying: Bool
    var accent: Color

    private let barCount = 5
    /// Envelope across the bars, so the shape reads as a little waveform.
    private let envelope: [Double] = [0.55, 0.82, 1.0, 0.82, 0.55]

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let levels = (0..<barCount).map { level($0, t) }
            let average = levels.reduce(0, +) / Double(barCount)

            ZStack {
                // Halo behind the bars.
                Capsule()
                    .fill(accent)
                    .frame(width: 34, height: 16)
                    .blur(radius: 8)
                    .opacity(isPlaying ? 0.25 + 0.35 * average : 0)

                HStack(alignment: .center, spacing: 2.5) {
                    ForEach(0..<barCount, id: \.self) { index in
                        Capsule()
                            .fill(LinearGradient(colors: [accent.lightened(0.45), accent],
                                                 startPoint: .top, endPoint: .bottom))
                            .frame(width: 3, height: 3 + 12 * levels[index])
                            .shadow(color: accent.opacity(isPlaying ? 0.85 : 0), radius: 3)
                    }
                }
            }
            .animation(.easeOut(duration: 0.35), value: isPlaying)
        }
        .frame(width: 36, height: 18)
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
