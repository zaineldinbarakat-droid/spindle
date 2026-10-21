import SwiftUI

/// How the current track's artwork is presented everywhere: as a record on a
/// turntable, or as the plain album cover.
enum ArtworkStyle: String, CaseIterable, Identifiable {
    case vinyl
    case cover

    static let storageKey = "artworkStyle"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .vinyl: return "Vinyl Record"
        case .cover: return "Album Cover"
        }
    }
}

/// The turntable or the cover, depending on the user's choice. `size` is the record
/// diameter, or the cover's edge length; the view sizes its own frame.
///
/// `@AppStorage` rather than an environment object: it is read from the notch, the
/// widgets and the backdrop, which are separate windows, and AppStorage observes
/// UserDefaults directly, so flipping the setting updates all of them at once.
struct DeckView: View {
    var size: CGFloat
    /// The album-coloured glow behind the cover (the notch turns it off unless asked).
    var glow: Bool = true

    @AppStorage(ArtworkStyle.storageKey) private var style: ArtworkStyle = .vinyl

    var body: some View {
        Group {
            switch style {
            case .vinyl:
                TurntableView(diameter: size)
                    .frame(width: size * TurntableView.widthFactor, height: size * TurntableView.heightFactor)
            case .cover:
                CoverArtView(size: size, glow: glow)
                    .frame(width: size, height: size)
            }
        }
        .animation(.notch, value: style)
    }
}

/// The album cover as a slightly lifted square. It sinks back a touch when paused, the
/// way the record stops spinning, so the two modes give the same feedback.
struct CoverArtView: View {
    var size: CGFloat
    var glow: Bool = true

    @EnvironmentObject private var player: PlayerManager

    private var cornerRadius: CGFloat { size * 0.07 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        ZStack {
            // Under real artwork: black, so no colour can fringe its antialiased edge.
            // The colour only stands in while there's no cover to show.
            if player.artwork != nil || !glow {
                shape.fill(player.artwork == nil ? Color(white: 0.14) : .black)
            } else {
                shape.fill(
                    LinearGradient(colors: [player.accent.opacity(0.9), player.accent.opacity(0.45)],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                )
            }

            if let artwork = player.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.32, weight: .medium))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
        .shadow(color: player.accent.opacity(glow ? 0.35 : 0), radius: size * 0.12, y: size * 0.04)
        .shadow(color: .black.opacity(0.5), radius: size * 0.05, y: size * 0.03)
        .scaleEffect(player.snapshot.isPlaying ? 1 : 0.94)
        .animation(.spring(response: 0.5, dampingFraction: 0.8), value: player.snapshot.isPlaying)
        .animation(.easeOut(duration: 0.35), value: player.artwork)
        .contentShape(shape)
        .onTapGesture { player.openSourceApp() }
        .pointingHandOnHover()
        .help("Open \(player.sourceProvider.displayName)")
    }
}

/// Tiny version for the collapsed notch: a spinning record or a rounded cover.
struct ArtworkThumbnail: View {
    var size: CGFloat

    @EnvironmentObject private var player: PlayerManager
    @AppStorage(ArtworkStyle.storageKey) private var style: ArtworkStyle = .vinyl

    var body: some View {
        Group {
            switch style {
            case .vinyl:
                VinylView(artwork: player.artwork,
                          accent: player.accent,
                          isSpinning: player.snapshot.isPlaying)
            case .cover:
                ZStack {
                    RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                        .fill(player.artwork == nil ? Color(white: 0.2) : .black)
                    if let artwork = player.artwork {
                        Image(nsImage: artwork)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            }
        }
        .frame(width: size, height: size)
    }
}
