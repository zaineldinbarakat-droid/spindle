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
                    // The light behind the cover: only with the cover glow on.
                    RadialGradient(colors: [player.accent.opacity(viewModel.coverGlow ? (isExpanded ? 0.32 : 0.18) : 0), .clear],
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
                        // The light behind the cover: only with the cover glow on.
                        RadialGradient(colors: [player.accent.opacity(viewModel.coverGlow ? 0.3 : 0), .clear],
                                       center: .init(x: 0.2, y: 0.7),
                                       startRadius: 4,
                                       endRadius: 280)
                    )
                    .mask(belowNotchMask)
                )
            } else {
                shape.fill(Theme.panel)
            }

        case .liquidGlass where !isExpanded:
            // Closed, the pill stays black like the hardware notch it hugs: clear glass
            // there would show the menu bar through the wings beside the camera.
            shape.fill(Theme.panel)

        case .liquidGlass:
            if #available(macOS 26, *) {
                LiquidGlassFill(clarity: viewModel.glassClarity,
                                tint: viewModel.glassTinted ? player.accent : nil,
                                bottomRadius: shape.bottomRadius)
            } else {
                shape.fill(Theme.panel)
            }
        }
    }
}

extension NotchBackground {
    /// How far down the panel the notch strip reaches, as a fraction of its height.
    var notchFraction: CGFloat {
        min(viewModel.metrics.notchHeight / viewModel.metrics.panelSize.height, 0.5)
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

/// Apple's Liquid Glass with a continuous clarity control, from AppKit's own
/// `NSGlassEffectView` — the same glass macOS draws its windows and controls with.
///
/// - Clear (top of the slider): the see-through lensing glass. What's behind stays
///   sharp, and the edges bend and catch the light. (The public `.clear` style, over
///   another app's windows, comes out as a heavy frost; see `AppleGlass`.)
/// - Frosted (bottom): the system's frosted material over it, dimmed a touch.
/// In between, the frost fades in proportion, so the slider has no jumps. Shaped as
/// a panel hanging from the top edge: its upper corners sit above the window, off
/// screen, so only the rounded bottom shows.
@available(macOS 26, *)
struct LiquidGlassFill: View {
    var clarity: Double
    var tint: Color?
    var bottomRadius: CGFloat

    var body: some View {
        let frost = 1 - min(max(clarity, 0), 1)
        let shape = BottomRoundedRectangle(radius: bottomRadius)
        ZStack {
            AppleGlass(tint: tint.map { NSColor($0).withAlphaComponent(0.25) }, cornerRadius: bottomRadius)
                .padding(.top, -bottomRadius)
            BehindWindowBlur()
                .clipShape(shape)
                .opacity(frost)
            // A breath of shade even when clear, so white type stays readable over a
            // bright window behind.
            shape.fill(Color.black.opacity(0.1 + 0.22 * frost))
        }
        .animation(.easeInOut(duration: 0.25), value: clarity)
    }
}

@available(macOS 26, *)
private struct AppleGlass: NSViewRepresentable {
    var tint: NSColor?
    var cornerRadius: CGFloat

    /// The lensing variant of Apple's glass. NSGlassEffectView's public styles, placed
    /// over other apps' windows, blur them heavily — even `.clear` reads as frosted.
    /// This variant (a private setting of the same view, checked on macOS 27) keeps
    /// what's behind sharp and refracts it at the edges, like Apple's own clear glass.
    /// If a later macOS drops the setting, the public clear style stands in.
    static let lensingVariant = 11

    func makeNSView(context: Context) -> NSGlassEffectView {
        let view = NSGlassEffectView()
        view.style = .clear
        if view.responds(to: NSSelectorFromString("set_variant:")) {
            view.setValue(Self.lensingVariant, forKey: "_variant")
        }
        return view
    }

    func updateNSView(_ view: NSGlassEffectView, context: Context) {
        view.cornerRadius = cornerRadius
        view.tintColor = tint
    }
}

/// Square at the top, rounded at the bottom: a panel hanging from the screen edge.
struct BottomRoundedRectangle: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }
    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addArc(center: CGPoint(x: rect.maxX - r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addArc(center: CGPoint(x: rect.minX + r, y: rect.maxY - r), radius: r,
                    startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        path.closeSubpath()
        return path
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
