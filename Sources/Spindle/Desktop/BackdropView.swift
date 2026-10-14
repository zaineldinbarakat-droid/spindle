import SwiftUI

/// The full-screen scene: a turntable on a walnut plinth in a dim room washed with the
/// cover's colour, big serif type beside it.
///
/// Used twice — as a wallpaper-level backdrop behind the desktop icons (not
/// interactive, so it never steals a click) and as a full-screen window (interactive:
/// drag the tonearm, use the transport).
struct BackdropView: View {
    var isInteractive: Bool

    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var timer: PomodoroTimer
    @AppStorage(ArtworkStyle.storageKey) private var style: ArtworkStyle = .vinyl

    var body: some View {
        GeometryReader { geo in
            let diameter = min(geo.size.height * 0.58, geo.size.width * 0.30)

            ZStack {
                ambience

                HStack(alignment: .center, spacing: geo.size.width * 0.05) {
                    if style == .vinyl {
                        deck(diameter: diameter)
                    } else {
                        CoverArtView(size: diameter * 1.2)
                            .allowsHitTesting(isInteractive)
                    }
                    info(diameter: diameter)
                        .frame(maxWidth: geo.size.width * 0.34, alignment: .leading)
                }
                .padding(.horizontal, geo.size.width * 0.06)

                VStack {
                    Spacer()
                    footer
                }
                .padding(28)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
    }

    // MARK: - Room

    private var ambience: some View {
        ZStack {
            Color(red: 0.06, green: 0.045, blue: 0.035)

            if let artwork = player.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .blur(radius: 90)
                    .saturation(1.2)
                    .opacity(0.42)
                    .transition(.opacity)
            }

            RadialGradient(colors: [player.accent.opacity(0.28), .clear],
                           center: .init(x: 0.32, y: 0.5),
                           startRadius: 40, endRadius: 900)

            // Vignette.
            RadialGradient(colors: [.clear, .black.opacity(0.75)],
                           center: .center, startRadius: 200, endRadius: 1400)

            FilmGrain()
                .opacity(0.10)
                .blendMode(.overlay)
        }
        .clipped()
        .animation(.easeInOut(duration: 1.2), value: player.artwork)
        .allowsHitTesting(false)
    }

    // MARK: - Turntable

    private func deck(diameter: CGFloat) -> some View {
        let width = diameter * 1.55 + diameter * 0.22
        let headroom = diameter * 0.26
        let height = diameter * 1.18 + diameter * 0.26 + headroom

        return ZStack(alignment: .topLeading) {
            WalnutPlinth(cornerRadius: diameter * 0.08)
                .shadow(color: .black.opacity(0.6), radius: diameter * 0.12, y: diameter * 0.06)

            TurntableView(diameter: diameter)
                .frame(width: diameter * 1.55, height: diameter * 1.18)
                .padding(diameter * 0.11)
                .padding(.top, headroom)
                .allowsHitTesting(isInteractive)

            // Speed selector and pilot light, bottom right of the plinth.
            HStack(spacing: diameter * 0.04) {
                Text("33⅓")
                    .font(.system(size: diameter * 0.045, weight: .bold, design: .serif))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                Circle()
                    .fill(player.snapshot.isPlaying ? Color.orange : Color(white: 0.25))
                    .frame(width: diameter * 0.03, height: diameter * 0.03)
                    .shadow(color: .orange.opacity(player.snapshot.isPlaying ? 0.9 : 0),
                            radius: diameter * 0.03)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .padding(diameter * 0.06)
        }
        .frame(width: width, height: height)
    }

    // MARK: - Type

    private func info(diameter: CGFloat) -> some View {
        let titleSize = max(diameter * 0.13, 22)

        return VStack(alignment: .leading, spacing: diameter * 0.04) {
            Text(player.snapshot.isPlaying ? "NOW SPINNING" : (player.snapshot.hasTrack ? "ON THE PLATTER" : "SPINDLE"))
                .font(.system(size: max(diameter * 0.04, 10), weight: .bold))
                .kerning(3)
                .foregroundStyle(player.accent)

            Text(player.snapshot.hasTrack ? player.snapshot.title : "Drop the needle")
                .font(.system(size: titleSize, weight: .semibold, design: .serif))
                .foregroundStyle(Theme.cream)
                .lineLimit(3)
                .minimumScaleFactor(0.5)

            if player.snapshot.hasTrack {
                Text(player.snapshot.artist)
                    .font(.system(size: titleSize * 0.42, weight: .medium))
                    .foregroundStyle(Theme.cream.opacity(0.75))
                    .lineLimit(1)
                if !player.snapshot.album.isEmpty {
                    Text(player.snapshot.album)
                        .font(.system(size: titleSize * 0.32, weight: .regular, design: .serif))
                        .italic()
                        .foregroundStyle(Theme.cream.opacity(0.5))
                        .lineLimit(1)
                }
            } else {
                Text("Play something in Music or Spotify.")
                    .font(.system(size: titleSize * 0.36))
                    .foregroundStyle(Theme.cream.opacity(0.55))
            }

            if isInteractive {
                ProgressBar()
                    .frame(maxWidth: 420)
                    .padding(.top, diameter * 0.04)
                TransportControls()
            } else {
                PassiveProgress()
                    .frame(maxWidth: 420, maxHeight: 3)
                    .padding(.top, diameter * 0.04)
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(alignment: .bottom) {
            TimelineView(.everyMinute) { context in
                Text(context.date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 28, weight: .light, design: .serif))
                    .foregroundStyle(Theme.cream.opacity(0.55))
            }

            Spacer()

            if timer.isActive {
                HStack(spacing: 8) {
                    Image(systemName: timer.phase.symbol)
                    Text("\(timer.phase.title) · \(timer.remainingString)")
                        .monospacedDigit()
                }
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(timer.phase.color)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.black.opacity(0.35)))
            }

            if isInteractive {
                Text("esc to exit")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.cream.opacity(0.3))
                    .padding(.leading, 14)
            }
        }
    }
}

/// A thin, read-only progress line for the wallpaper version, which can't be clicked.
private struct PassiveProgress: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(player.accent)
                        .frame(width: geo.size.width * player.displayFraction)
                }
            }
        }
    }
}

/// Static film grain, seeded so it's identical every launch. Drawn once.
private struct FilmGrain: View {
    var body: some View {
        Canvas { context, size in
            var seed: UInt64 = 0xF11A
            func random() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(1 << 31)
            }
            let count = Int(size.width * size.height / 260)
            for _ in 0..<count {
                let rect = CGRect(x: random() * size.width, y: random() * size.height,
                                  width: 1.2, height: 1.2)
                context.fill(Path(rect),
                             with: .color(random() > 0.5 ? .white : .black))
            }
        }
        .drawingGroup()
    }
}
