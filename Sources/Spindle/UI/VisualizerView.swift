import SwiftUI

/// Bars that bounce while music plays.
///
/// This is decorative, not a spectrum analyser: reading the system audio output would
/// need a loopback device or an audio tap, neither of which a passive widget should
/// install. The motion is generated from layered sine waves at incommensurable
/// frequencies so it never visibly loops.
struct VisualizerView: View {
    var isPlaying: Bool
    var accent: Color
    var barCount: Int = 4

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isPlaying)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate

            HStack(alignment: .center, spacing: 2.5) {
                ForEach(Array(0..<barCount), id: \.self) { index in
                    Capsule()
                        .fill(accent.opacity(0.9))
                        .frame(width: 2.5, height: height(for: index, at: t))
                }
            }
            .animation(.easeOut(duration: 0.12), value: isPlaying)
        }
        .frame(height: 14)
    }

    private func height(for index: Int, at time: TimeInterval) -> CGFloat {
        guard isPlaying else { return 2.5 }
        let phase = Double(index) * 1.7
        let wave = sin(time * 6.3 + phase) * 0.5
            + sin(time * 9.7 + phase * 2.1) * 0.3
            + sin(time * 3.1 + phase * 0.7) * 0.2
        let normalized = (wave + 1) / 2
        return 3 + CGFloat(normalized) * 11
    }
}
