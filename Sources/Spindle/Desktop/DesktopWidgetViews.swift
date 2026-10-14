import SwiftUI

enum DesktopWidgetKind: String, CaseIterable, Identifiable {
    /// Small square: a record player and the song title.
    case record
    /// Wide: turntable, track info, scrubber and transport.
    case turntable

    var id: String { rawValue }

    var title: String {
        switch self {
        case .record: return "Record (Small)"
        case .turntable: return "Turntable (Wide)"
        }
    }

    var size: CGSize {
        switch self {
        case .record: return CGSize(width: 210, height: 222)
        case .turntable: return CGSize(width: 470, height: 236)
        }
    }

    var defaultsKey: Defaults.Key {
        switch self {
        case .record: return .recordWidgetVisible
        case .turntable: return .turntableWidgetVisible
        }
    }
}

/// Walnut plinth every widget sits on, plus drag-to-move and the right-click menu.
struct WidgetChrome<Content: View>: View {
    @ObservedObject var mover: WindowMover
    var onRemove: () -> Void
    @ViewBuilder var content: Content

    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        ZStack {
            WalnutPlinth(cornerRadius: 24)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .onChanged { _ in mover.drag() }
                        .onEnded { _ in mover.end() }
                )

            content
        }
        // A little inset so the plinth's shadow isn't clipped by the window edge.
        .padding(8)
        .environment(\.colorScheme, .dark)
        .contextMenu {
            Button("Open \(player.sourceProvider.displayName)") { player.openSourceApp() }
            Divider()
            Button("Remove Widget", action: onRemove)
        }
    }
}

/// Dark walnut with a faint grain, a bevelled edge and a soft drop shadow.
struct WalnutPlinth: View {
    var cornerRadius: CGFloat

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        shape
            .fill(LinearGradient(colors: [Theme.walnutLight, Theme.walnutDark],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(WoodGrain().clipShape(shape).opacity(0.55))
            .overlay(
                shape.strokeBorder(
                    LinearGradient(colors: [Color.white.opacity(0.22), Color.black.opacity(0.4)],
                                   startPoint: .top, endPoint: .bottom),
                    lineWidth: 1.2)
            )
            .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
    }
}

/// Wavy horizontal grain lines. Drawn once and cached by `drawingGroup`.
struct WoodGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0x5EED
            func random() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            var y: CGFloat = 0
            while y < size.height {
                var path = Path()
                let amplitude = 1.5 + random() * 3
                let frequency = 0.008 + random() * 0.012
                let phase = random() * .pi * 2
                path.move(to: CGPoint(x: 0, y: y))
                var x: CGFloat = 0
                while x <= size.width {
                    path.addLine(to: CGPoint(x: x, y: y + sin(x * frequency + phase) * amplitude))
                    x += 6
                }
                context.stroke(path,
                               with: .color(Color.black.opacity(0.12 + random() * 0.18)),
                               lineWidth: 0.6 + random() * 1.4)
                y += 3 + random() * 6
            }
        }
        .drawingGroup()
        .allowsHitTesting(false)
    }
}

// MARK: - Small

struct RecordWidgetView: View {
    @EnvironmentObject private var player: PlayerManager
    @AppStorage(ArtworkStyle.storageKey) private var style: ArtworkStyle = .vinyl

    var body: some View {
        VStack(spacing: 6) {
            // The tonearm's counterweight needs headroom above the record; a cover doesn't.
            DeckView(size: style == .vinyl ? 100 : 118)
                .padding(.top, style == .vinyl ? 34 : 20)
                .padding(.bottom, style == .vinyl ? 0 : 6)

            VStack(spacing: 1) {
                MarqueeText(text: player.snapshot.hasTrack ? player.snapshot.title : "Nothing playing",
                            font: .system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.cream)
                Text(player.snapshot.hasTrack ? player.snapshot.artist : "Open Music or Spotify")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.cream.opacity(0.6))
                    .lineLimit(1)
            }
            .padding(.horizontal, 14)

            Spacer(minLength: 0)
        }
    }
}

// MARK: - Wide

struct TurntableWidgetView: View {
    @EnvironmentObject private var player: PlayerManager
    @AppStorage(ArtworkStyle.storageKey) private var style: ArtworkStyle = .vinyl

    var body: some View {
        HStack(alignment: .center, spacing: style == .vinyl ? 6 : 20) {
            DeckView(size: style == .vinyl ? 140 : 168)
                .padding(.leading, style == .vinyl ? 8 : 18)
                .padding(.top, style == .vinyl ? 22 : 0)

            VStack(alignment: .leading, spacing: 10) {
                TrackInfoView()
                ProgressBar()
                TransportControls()
                    .scaleEffect(0.86, anchor: .leading)
            }
            .padding(.trailing, 18)
        }
    }
}
