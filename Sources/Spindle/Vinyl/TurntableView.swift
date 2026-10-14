import SwiftUI

/// Platter + record + tonearm, sharing one coordinate space so the arm's drag maths
/// line up with where the record actually is.
struct TurntableView: View {
    @EnvironmentObject private var player: PlayerManager

    var diameter: CGFloat

    private let space = "turntable"

    var body: some View {
        ZStack {
            let radius = diameter / 2
            let center = CGPoint(x: diameter / 2, y: diameter / 2)
            let geo = TonearmGeometry(center: center, radius: radius)

            platter(radius: radius)
                .position(center)

            VinylView(artwork: player.artwork,
                      accent: player.accent,
                      isSpinning: player.snapshot.isPlaying)
                .frame(width: diameter, height: diameter)
                // Clicking the record brings its app forward. The tonearm sits on top
                // and only claims its own outline, so the two never fight.
                .contentShape(Circle())
                .onTapGesture { player.openSourceApp() }
                .pointingHandOnHover()
                .help("Open \(player.sourceProvider.displayName)")
                .position(center)

            TonearmView(
                geometry: geo,
                progress: player.displayFraction,
                isEngaged: player.snapshot.hasTrack,
                accent: player.accent,
                coordinateSpace: space,
                onScrubBegan: { player.beginScrub(fraction: $0) },
                onScrubChanged: { player.updateScrub(fraction: $0) },
                onScrubEnded: { player.endScrub() }
            )
        }
        // The arm pivot sits outside the record, so the container has to be wider.
        .frame(width: diameter * 1.55, height: diameter * 1.18, alignment: .topLeading)
        .coordinateSpace(name: space)
    }

    /// Felt mat peeking out from under the record.
    private func platter(radius: CGFloat) -> some View {
        Circle()
            .fill(
                RadialGradient(colors: [Color(white: 0.20), Color(white: 0.10)],
                               center: .center, startRadius: 0, endRadius: radius * 1.08)
            )
            .frame(width: radius * 2.12, height: radius * 2.12)
            .shadow(color: .black.opacity(0.7), radius: radius * 0.12, y: radius * 0.05)
    }
}
