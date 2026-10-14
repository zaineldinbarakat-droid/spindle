import SwiftUI

struct TransportControls: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        HStack(spacing: 18) {
            TransportButton(symbol: "backward.fill", size: 15) { player.previous() }

            TransportButton(symbol: player.snapshot.isPlaying ? "pause.fill" : "play.fill",
                            size: 20,
                            prominent: true) {
                player.togglePlayPause()
            }

            TransportButton(symbol: "forward.fill", size: 15) { player.next() }
        }
        .disabled(!player.snapshot.hasTrack)
        .opacity(player.snapshot.hasTrack ? 1 : 0.35)
    }
}

private struct TransportButton: View {
    var symbol: String
    var size: CGFloat
    var prominent: Bool = false
    var action: () -> Void

    @State private var isHovering = false
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: prominent ? 42 : 34, height: prominent ? 42 : 34)
                .background(
                    Circle()
                        .fill(Color.white.opacity(prominent ? 0.14 : 0.08))
                        .opacity(isHovering || prominent ? 1 : 0)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .scaleEffect(isPressed ? 0.88 : (isHovering ? 1.06 : 1.0))
        .animation(.notchQuick, value: isPressed)
        .animation(.notchQuick, value: isHovering)
        .onHover { isHovering = $0 }
        // Tracks the press so the button feels physical; Button alone gives no such hook.
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in isPressed = true }
                .onEnded { _ in isPressed = false }
        )
    }
}
