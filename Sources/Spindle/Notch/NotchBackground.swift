import SwiftUI

/// Paints the notch shape in the user's chosen style.
///
/// The shadow sits on a flattened copy of the shape (`compositingGroup`) so that while
/// the panel grows, the window server blurs one simple layer per frame instead of
/// re-shadowing every gradient stacked inside it — which is where the hitch was.
struct NotchBackground: View {
    var shape: NotchShape
    var isExpanded: Bool

    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        fill
            .compositingGroup()
            .shadow(color: .black.opacity(isExpanded ? 0.4 : 0), radius: 14, y: 7)
            // A new cover cross-fades the colour rather than cutting.
            .animation(.easeInOut(duration: 0.9), value: player.accent)
    }

    @ViewBuilder
    private var fill: some View {
        switch viewModel.style {
        case .black:
            shape
                .fill(Theme.panel)
                .overlay(
                    // Cover art bleeding a faint glow into the panel.
                    shape.fill(
                        RadialGradient(colors: [player.accent.opacity(isExpanded ? 0.18 : 0), .clear],
                                       center: .init(x: 0.2, y: 0.6),
                                       startRadius: 10,
                                       endRadius: 280)
                    )
                )

        case .songColor:
            // Deep enough that white text stays legible on any cover, saturated enough
            // that it's unmistakably the song's colour. Expanded, the top edge stays
            // darker so the panel still melts into the black hardware notch. Collapsed,
            // the pill is only as tall as the menu bar, so it takes the colour evenly —
            // otherwise the tint is too thin to notice.
            shape.fill(
                LinearGradient(colors: isExpanded
                                ? [player.accent.darkened(0.74), player.accent.darkened(0.48), player.accent.darkened(0.58)]
                                : [player.accent.darkened(0.5), player.accent.darkened(0.42)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                shape.fill(
                    RadialGradient(colors: [player.accent.opacity(isExpanded ? 0.32 : 0.18), .clear],
                                   center: .init(x: 0.2, y: 0.65),
                                   startRadius: 4,
                                   endRadius: 300)
                )
            )

        case .liquidGlass:
            if #available(macOS 26, *) {
                Color.clear
                    .glassEffect(.regular.tint(player.accent.opacity(0.32)), in: shape)
                    // Glass over a bright desktop would wash out white text; a thin
                    // dark scrim keeps it readable without losing the refraction.
                    .overlay(shape.fill(Color.black.opacity(isExpanded ? 0.28 : 0.45)))
            } else {
                shape.fill(Theme.panel)
            }
        }
    }
}

extension Color {
    /// Mixes toward black by `fraction` (0 = unchanged, 1 = black).
    func darkened(_ fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(nsColor: base.blended(withFraction: fraction, of: .black) ?? base)
    }
}
