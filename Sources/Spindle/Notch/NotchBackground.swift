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
            // Shadow only *below* the panel: one cast all round also darkened the
            // menu bar beside the notch, a halo that read as a bump as it opened.
            .background(alignment: .bottom) {
                RoundedRectangle(cornerRadius: Theme.outerCornerRadius, style: .continuous)
                    .fill(Color.black.opacity(isExpanded ? 0.45 : 0))
                    .frame(height: 36)
                    .padding(.horizontal, 26)
                    .blur(radius: 16)
                    .offset(y: 12)
            }
            // A new cover cross-fades the colour rather than cutting.
            .animation(.easeInOut(duration: 0.9), value: player.accent)
    }

    @ViewBuilder
    private var fill: some View {
        switch viewModel.style {
        case .black:
            // Black means black: no album colour anywhere, so it stays one with the
            // hardware notch. (The colour lives in the playing indicator instead.)
            shape.fill(Theme.panel)

        case .songColor where viewModel.tintNotch:
            // Opted in: the colour reaches right up into the notch.
            shape.fill(
                LinearGradient(colors: isExpanded
                                ? [player.accent.darkened(0.74), player.accent.darkened(0.48), player.accent.darkened(0.58)]
                                : [player.accent.darkened(0.5), player.accent.darkened(0.42)],
                               startPoint: .top, endPoint: .bottom)
            )
            .overlay(
                shape.fill(
                    RadialGradient(colors: [player.accent.opacity(isExpanded ? 0.32 : 0.18), .clear],
                                   center: .init(x: 0.2, y: 0.65), startRadius: 4, endRadius: 300)
                )
            )

        case .songColor:
            // The default: the colour never touches the notch. The collapsed pill and
            // the strip beside the camera stay pure black like the hardware, and the
            // cover's colour rises in from below that strip.
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
                LiquidGlassFill(shape: shape,
                                clarity: viewModel.glassClarity,
                                tint: viewModel.glassTinted ? player.accent : nil)
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

/// Apple's Liquid Glass with a continuous clarity control.
///
/// The base is always Apple's *clear* glass — properly see-through, refracting what's
/// behind it at the edges. Frosting is layered on top in proportion: a behind-window
/// blur and a little dimming, both fading to nothing as clarity rises. One continuous
/// slider, no jump between "regular" and "clear" halfway along.
@available(macOS 26, *)
struct LiquidGlassFill: View {
    var shape: NotchShape
    var clarity: Double
    var tint: Color?

    var body: some View {
        let frost = 1 - min(max(clarity, 0), 1)
        ZStack {
            Color.clear
                .glassEffect(.clear.tint(tint?.opacity(0.18 + 0.17 * frost)), in: shape)
            BehindWindowBlur()
                .mask(shape)
                .opacity(frost * 0.95)
            // A touch of dimming keeps white text readable over bright desktops.
            shape.fill(Color.black.opacity(0.08 + 0.32 * frost))
        }
        .animation(.easeInOut(duration: 0.25), value: clarity)
    }
}

/// The system's own frosted material, blurring whatever is behind the window.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
