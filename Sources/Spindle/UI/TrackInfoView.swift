import SwiftUI

struct TrackInfoView: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if player.snapshot.hasTrack {
                MarqueeText(text: player.snapshot.title,
                            font: .system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)

                MarqueeText(text: subtitle, font: .system(size: 11, weight: .regular))
                    .foregroundStyle(Theme.secondaryText)
            } else {
                Text("Nothing playing")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                Text(emptySubtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.tertiaryText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitle: String {
        let parts = [player.snapshot.artist, player.snapshot.album].filter { !$0.isEmpty }
        return parts.joined(separator: " — ")
    }

    private var emptySubtitle: String {
        if !player.deniedProviders.isEmpty {
            return "Allow Spindle to control your music app"
        }
        if player.availableProviders.isEmpty {
            return "Open Music or Spotify to begin"
        }
        return "Press play in \(player.availableProviders.map(\.displayName).joined(separator: " or "))"
    }
}

/// Scrolls text horizontally only when it overflows, pausing at each end.
struct MarqueeText: View {
    var text: String
    var font: Font

    @State private var textWidth: CGFloat = 0
    @State private var containerWidth: CGFloat = 0
    @State private var offset: CGFloat = 0

    private var overflow: CGFloat { max(textWidth - containerWidth, 0) }
    private var shouldScroll: Bool { overflow > 1 }

    var body: some View {
        GeometryReader { geo in
            Text(text)
                .font(font)
                .lineLimit(1)
                .fixedSize()
                .background(
                    GeometryReader { textGeo in
                        Color.clear.onAppear { textWidth = textGeo.size.width }
                            .onChange(of: text) { _, _ in textWidth = textGeo.size.width }
                    }
                )
                .offset(x: offset)
                .frame(width: geo.size.width, alignment: .leading)
                .clipped()
                .onAppear {
                    containerWidth = geo.size.width
                    restart()
                }
                .onChange(of: geo.size.width) { _, new in
                    containerWidth = new
                    restart()
                }
                .onChange(of: text) { _, _ in restart() }
        }
        .frame(height: lineHeight)
    }

    private var lineHeight: CGFloat { 18 }

    private func restart() {
        offset = 0
        guard shouldScroll else { return }
        // Constant speed rather than constant duration, so long titles don't race.
        let duration = Double(overflow) / 22.0
        withAnimation(
            .easeInOut(duration: duration)
            .delay(1.6)
            .repeatForever(autoreverses: true)
        ) {
            offset = -overflow
        }
    }
}
