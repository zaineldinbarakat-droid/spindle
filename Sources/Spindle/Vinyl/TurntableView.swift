import SwiftUI

/// Platter + record + tonearm, sharing one coordinate space so the arm's drag maths
/// line up with where the record actually is.
struct TurntableView: View {
    @EnvironmentObject private var player: PlayerManager
    @AppStorage(Defaults.Key.recordLabelSize.rawValue) private var labelSize = Double(Theme.Record.labelFraction)

    var diameter: CGFloat

    /// The deck's frame, as multiples of the record's diameter. The record is centred
    /// top to bottom with just enough room for the platter's rim, so whoever lays the
    /// deck out centres the record itself — not a box with empty space under it. The
    /// width leaves room for the arm's pivot to the right. Only the arm's counterweight
    /// reaches above the frame, so don't clip the deck vertically.
    static let widthFactor: CGFloat = 1.55
    static let heightFactor: CGFloat = 1.10

    private let space = "turntable"

    var body: some View {
        ZStack {
            let radius = diameter / 2
            let center = CGPoint(x: diameter * 0.53, y: diameter * Self.heightFactor / 2)
            let geo = TonearmGeometry(center: center, radius: radius, labelFraction: CGFloat(labelSize))

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
        .frame(width: diameter * Self.widthFactor, height: diameter * Self.heightFactor, alignment: .topLeading)
        .coordinateSpace(name: space)
    }

    /// The platter under the record: a dark rubber mat inside a machined aluminium rim
    /// that just shows round the record's edge, with the record's shadow on it.
    private func platter(radius: CGFloat) -> some View {
        let rim = radius * 2.10
        return ZStack {
            Circle()
                .fill(AngularGradient(colors: [Color(white: 0.46), Color(white: 0.20), Color(white: 0.38),
                                               Color(white: 0.16), Color(white: 0.42), Color(white: 0.22),
                                               Color(white: 0.46)],
                                      center: .center))
            Circle()
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.35), .white.opacity(0.04)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing),
                              lineWidth: max(radius * 0.008, 0.5))
            Circle()
                .fill(Color(white: 0.06))
                .padding(radius * 0.035)
            // The record's shadow, falling a touch down and right on the mat.
            Circle()
                .fill(Color.black.opacity(0.75))
                .frame(width: radius * 2.02, height: radius * 2.02)
                .offset(x: radius * 0.012, y: radius * 0.025)
                .blur(radius: radius * 0.025)
        }
        .frame(width: rim, height: rim)
        .shadow(color: .black.opacity(0.6), radius: radius * 0.08, y: radius * 0.04)
    }
}
