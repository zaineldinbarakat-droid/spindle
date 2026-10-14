import SwiftUI

/// Thin scrubber under the track info. Redundant with the tonearm, but the tonearm is
/// coarse — roughly 20 degrees of sweep for a whole side — so precise seeks need this.
struct ProgressBar: View {
    @EnvironmentObject private var player: PlayerManager

    @State private var isHovering = false
    @State private var isDragging = false

    private var height: CGFloat { isHovering || isDragging ? 6 : 3 }

    var body: some View {
        VStack(spacing: 5) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))

                    Capsule()
                        .fill(
                            LinearGradient(colors: [player.accent.opacity(0.85), player.accent],
                                           startPoint: .leading, endPoint: .trailing)
                        )
                        .frame(width: max(geo.size.width * player.displayFraction, 0))
                }
                .frame(height: height)
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let fraction = value.location.x / max(geo.size.width, 1)
                            if !isDragging {
                                isDragging = true
                                player.beginScrub(fraction: fraction)
                            } else {
                                player.updateScrub(fraction: fraction)
                            }
                        }
                        .onEnded { _ in
                            isDragging = false
                            player.endScrub()
                        }
                )
            }
            .frame(height: 10)
            .animation(.notchQuick, value: height)
            .onHover { isHovering = $0 }

            HStack {
                Text(player.displayPosition.clockString)
                Spacer()
                Text(player.snapshot.duration.clockString)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .foregroundStyle(Theme.tertiaryText)
            .monospacedDigit()
        }
        .disabled(!player.snapshot.hasTrack)
    }
}
