import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var timer: PomodoroTimer

    @AppStorage(ArtworkStyle.storageKey) private var artworkStyle: ArtworkStyle = .vinyl

    /// One black shape that grows out of the notch and shrinks back into it, rather
    /// than two views cross-fading. The expanded content is laid out at full size from
    /// the first frame and simply revealed by the growing clip, so nothing reflows
    /// mid-animation.
    var body: some View {
        ZStack(alignment: .top) {
            // The window is always full expanded size; this keeps it invisible and
            // click-through everywhere the panel isn't actually drawn.
            Color.clear

            if !viewModel.isZenHidden && (viewModel.isExpanded || player.snapshot.hasTrack || timer.isActive) {
                island
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .animation(.easeInOut(duration: 0.25), value: viewModel.isZenHidden)
    }

    private var collapsedSize: CGSize {
        CGSize(width: viewModel.metrics.notchWidth + Theme.collapsedWingWidth * 2,
               height: viewModel.metrics.notchHeight)
    }

    private var expandedSize: CGSize { viewModel.metrics.panelSize }

    private var island: some View {
        let expanded = viewModel.isExpanded
        let size = expanded ? expandedSize : collapsedSize
        let shape = NotchShape(topRadius: Theme.notchCornerRadius,
                               bottomRadius: expanded ? min(CGFloat(viewModel.panelCornerRadius) * viewModel.metrics.panelScale,
                                                            size.height / 2)
                                                      : Theme.notchCornerRadius)

        return ZStack(alignment: .top) {
            NotchBackground(shape: shape, isExpanded: expanded)

            ZStack(alignment: .top) {
                if expanded {
                    expandedContent
                        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                        .transition(.asymmetric(
                            // Resolves out of a blur just behind the growing shape.
                            insertion: .islandContentIn.animation(viewModel.motion.contentIn),
                            removal: .islandContentIn.animation(viewModel.motion.contentOut)
                        ))
                } else {
                    collapsedContent
                        .frame(width: collapsedSize.width, height: collapsedSize.height)
                        .transition(.asymmetric(
                            insertion: .islandContentIn.animation(viewModel.motion.pillIn),
                            removal: .islandContentIn.animation(.easeIn(duration: 0.08))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
        // Reshaping from Settings glides rather than jumps.
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: viewModel.metrics)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: viewModel.panelCornerRadius)
        .animation(.spring(response: 0.32, dampingFraction: 0.9), value: viewModel.coverScale)
    }

    // MARK: - Collapsed

    /// Two small wings hugging the physical notch. The middle is left empty because on a
    /// notched display there are no pixels there to draw into.
    private var collapsedContent: some View {
        let metrics = viewModel.metrics
        let thumb = metrics.notchHeight - 10

        return HStack(spacing: 0) {
            // Centred in its wing (clear of the shoulder where the shape meets the
            // bezel) rather than pushed against the outer edge.
            HStack(spacing: 0) {
                if viewModel.collapsedShowsCover {
                    CollapsedCover(size: thumb)
                } else {
                    ArtworkThumbnail(size: thumb)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.leading, Theme.notchCornerRadius)
            .frame(width: Theme.collapsedWingWidth)

            Spacer(minLength: 0)
                .frame(width: metrics.notchWidth)

            HStack(spacing: 0) {
                if timer.isActive {
                    CollapsedCountdown()
                } else if viewModel.showVisualizer {
                    RadianceView(isPlaying: player.snapshot.isPlaying,
                                 color: viewModel.indicatorColor(accent: player.accent),
                                 style: viewModel.indicatorStyle,
                                 brightness: viewModel.indicatorBrightness,
                                 glow: viewModel.indicatorGlow,
                                 live: viewModel.liveWaves)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.trailing, Theme.notchCornerRadius)
            .frame(width: Theme.collapsedWingWidth)
        }
    }

    // MARK: - Expanded

    /// The strip beside the camera at the notch's real height, then the tabs. The tabs
    /// are laid out at their design size (wider or taller if asked — more room, never
    /// stretched) and scaled as a whole, so Size keeps every proportion.
    private var expandedContent: some View {
        let metrics = viewModel.metrics
        let scale = metrics.panelScale
        let page = metrics.pageSize

        return VStack(spacing: 0) {
            header
                .frame(height: metrics.notchHeight)

            pages(size: page, scale: scale)
                .frame(width: page.width, height: page.height)
                .scaleEffect(scale, anchor: .top)
                .frame(width: page.width * scale, height: page.height * scale, alignment: .top)
        }
    }

    /// The player and the timer side by side, like photos in a strip: a two-finger swipe
    /// drags them (see NotchWindowController) and they settle on a page with a spring.
    private func pages(size: CGSize, scale: CGFloat) -> some View {
        let index: CGFloat = viewModel.tab == .player ? 0 : 1
        return HStack(spacing: 0) {
            playerBody
                .frame(width: size.width, height: size.height)
            FocusView(dialSize: 112, compact: true)
                .frame(width: size.width, height: size.height)
        }
        .frame(width: size.width, height: size.height, alignment: .leading)
        .offset(x: -index * size.width + viewModel.swipeOffset / max(scale, 0.1))
        .animation(NotchViewModel.pageSpring, value: viewModel.tab)
        .frame(width: size.width, height: size.height, alignment: .leading)
        // Clipped sideways only, for the swipe. Clipped at the top too, the tonearm's
        // counterweight (and on big covers the record) got cut off flat under the strip.
        .mask(Rectangle().padding(.vertical, -size.height))
    }

    private var playerBody: some View {
        HStack(alignment: .center, spacing: artworkStyle == .cover ? 18 : 10) {
            DeckView(size: 124 * CGFloat(viewModel.coverScale), glow: viewModel.coverGlow)

            VStack(alignment: .leading, spacing: 10) {
                TrackInfoView()
                    .contentShape(Rectangle())
                    .onTapGesture { player.openSourceApp() }
                ProgressBar()
                HStack {
                    TransportControls()
                    Spacer()
                    if viewModel.panelWaves {
                        // The song's waves, after Vinylpod: the same look as the
                        // notch's indicator, larger, in the room beside the controls.
                        RadianceView(isPlaying: player.snapshot.isPlaying,
                                     color: viewModel.indicatorColor(accent: player.accent),
                                     style: viewModel.indicatorStyle,
                                     brightness: viewModel.indicatorBrightness,
                                     glow: viewModel.indicatorGlow,
                                     layout: .panel,
                                     live: viewModel.liveWaves)
                            .transition(.opacity)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 20)
        }
        .padding(.leading, artworkStyle == .cover ? 26 : 22)
        .padding(.bottom, 6)
    }

    /// Sits in the strip beside the notch: provider on the left, controls on the right.
    private var header: some View {
        let metrics = viewModel.metrics

        let wingWidth = (metrics.panelSize.width - metrics.notchWidth) / 2

        return HStack(spacing: 0) {
            // Left of the notch stays empty: the album cover is how you open the app.
            Color.clear.frame(width: wingWidth, height: metrics.notchHeight)

            Spacer(minLength: metrics.notchWidth)

            HStack(spacing: 10) {
                Spacer(minLength: 0)

                if !player.deniedProviders.isEmpty {
                    Button {
                        player.openAutomationSettings()
                    } label: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(.yellow)
                    }
                    .buttonStyle(.plain)
                    .help("Spindle needs permission to control your music app")
                }

                TabSwitcher()

                Button {
                    SettingsWindow.show()
                } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
            .padding(.trailing, 16)
            .frame(width: wingWidth)
        }
    }
}

/// Record / timer switch in the header. The whole capsule is one button — anywhere on
/// it flips to the other tab — and the highlight slides across like the pages do.
private struct TabSwitcher: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var timer: PomodoroTimer
    @State private var isHovering = false

    var body: some View {
        Button {
            withAnimation(NotchViewModel.pageSpring) {
                viewModel.tab = viewModel.tab == .player ? .focus : .player
            }
        } label: {
            ZStack(alignment: viewModel.tab == .player ? .leading : .trailing) {
                Capsule().fill(Color.white.opacity(isHovering ? 0.12 : 0.08))
                Capsule().fill(Color.white.opacity(0.2))
                    .frame(width: 28)
                    .padding(2)
                HStack(spacing: 0) {
                    icon(.player, symbol: "opticaldisc.fill")
                    icon(.focus, symbol: "timer")
                }
                .padding(2)
            }
            .frame(width: 60, height: 24)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .animation(NotchViewModel.pageSpring, value: viewModel.tab)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .help(viewModel.tab == .player ? "Show the focus timer (or swipe with two fingers)"
                                       : "Show the player (or swipe with two fingers)")
    }

    private func icon(_ tab: NotchViewModel.Tab, symbol: String) -> some View {
        let selected = viewModel.tab == tab
        return Image(systemName: symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(selected ? Color.white : Theme.tertiaryText)
            // A running timer tints its tab so it's visible from the player side.
            .overlay(alignment: .topTrailing) {
                if tab == .focus && timer.isRunning && !selected {
                    Circle().fill(timer.phase.color).frame(width: 4, height: 4).offset(x: 3, y: -2)
                }
            }
            .frame(width: 28, height: 20)
    }
}

/// The album cover in the collapsed notch's left wing: small, rounded and crisp.
private struct CollapsedCover: View {
    var size: CGFloat
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
        ZStack {
            // Black under the artwork, so none of the album's colour shows at its edge.
            shape.fill(player.artwork == nil ? Color(white: 0.2) : .black)
            if let artwork = player.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fill)
                    .transition(.opacity)
            } else {
                Image(systemName: "music.note")
                    .font(.system(size: size * 0.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        // A neutral hairline: the album's colour stays out of the notch.
        .overlay(shape.strokeBorder(Color.white.opacity(0.12), lineWidth: 0.75))
        .animation(.easeOut(duration: 0.35), value: player.artwork)
    }
}

/// The countdown shown in the right wing of the collapsed notch.
private struct CollapsedCountdown: View {
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 4) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.15), lineWidth: 2)
                Circle()
                    .trim(from: 0, to: 1 - timer.progress)
                    .stroke(timer.phase.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 11, height: 11)

            Text(timer.remainingString)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(timer.isRunning ? timer.phase.color : Theme.tertiaryText)
        }
    }
}
