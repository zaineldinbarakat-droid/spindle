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
                    // Cover art glowing faintly into the panel, below the notch strip.
                    shape.fill(
                        RadialGradient(colors: [player.accent.opacity(isExpanded ? 0.18 : 0), .clear],
                                       center: .init(x: 0.2, y: 0.6),
                                       startRadius: 10,
                                       endRadius: 280)
                    )
                    .mask(belowNotchMask)
                )

        case .songColor:
            // The colour never touches the notch: the collapsed pill and the strip
            // beside the camera stay pure black like the hardware, and the cover's
            // colour rises in from below that strip.
            if isExpanded {
                shape.fill(
                    LinearGradient(stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: notchFraction),
                        .init(color: player.accent.darkened(0.6), location: min(notchFraction + 0.32, 1)),
                        .init(color: player.accent.darkened(0.52), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                )
                .overlay(
                    shape.fill(
                        RadialGradient(colors: [player.accent.opacity(0.3), .clear],
                                       center: .init(x: 0.2, y: 0.7),
                                       startRadius: 4,
                                       endRadius: 280)
                    )
                    .mask(belowNotchMask)
                )
            } else {
                shape.fill(Theme.panel)
            }

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

extension NotchBackground {
    /// How far down the panel the notch strip reaches, as a fraction of its height.
    var notchFraction: CGFloat {
        min(viewModel.metrics.notchHeight / Theme.expandedHeight, 0.5)
    }

    /// Transparent across the notch strip, opaque below it, with a short fade.
    var belowNotchMask: some View {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: notchFraction),
            .init(color: .black, location: min(notchFraction + 0.2, 1))
        ], startPoint: .top, endPoint: .bottom)
    }
}

extension Color {
    /// Mixes toward black by `fraction` (0 = unchanged, 1 = black).
    func darkened(_ fraction: CGFloat) -> Color {
        let base = NSColor(self).usingColorSpace(.sRGB) ?? .black
        return Color(nsColor: base.blended(withFraction: fraction, of: .black) ?? base)
    }
}
