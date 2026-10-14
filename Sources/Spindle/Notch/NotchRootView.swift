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

            if viewModel.isExpanded || player.snapshot.hasTrack || timer.isActive {
                island
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    private var collapsedSize: CGSize {
        CGSize(width: viewModel.metrics.notchWidth + Theme.collapsedWingWidth * 2,
               height: viewModel.metrics.notchHeight)
    }

    private var expandedSize: CGSize {
        CGSize(width: Theme.expandedWidth, height: Theme.expandedHeight)
    }

    private var island: some View {
        let expanded = viewModel.isExpanded
        let size = expanded ? expandedSize : collapsedSize
        let shape = NotchShape(topRadius: Theme.notchCornerRadius,
                               bottomRadius: expanded ? Theme.outerCornerRadius : Theme.notchCornerRadius)

        return ZStack(alignment: .top) {
            shape
                .fill(Theme.panel)
                .overlay(
                    // Cover art bleeding a faint glow into the panel.
                    shape.fill(
                        RadialGradient(colors: [player.accent.opacity(expanded ? 0.18 : 0), .clear],
                                       center: .init(x: 0.2, y: 0.6),
                                       startRadius: 10,
                                       endRadius: 280)
                    )
                )
                .shadow(color: .black.opacity(expanded ? 0.45 : 0), radius: 16, y: 8)

            ZStack(alignment: .top) {
                if expanded {
                    expandedContent
                        .frame(width: expandedSize.width, height: expandedSize.height, alignment: .top)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.22).delay(0.08)),
                            removal: .opacity.animation(.easeIn(duration: 0.1))
                        ))
                } else {
                    collapsedContent
                        .frame(width: collapsedSize.width, height: collapsedSize.height)
                        .transition(.asymmetric(
                            insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.12)),
                            removal: .opacity.animation(.easeIn(duration: 0.08))
                        ))
                }
            }
            .frame(width: size.width, height: size.height, alignment: .top)
            .clipShape(shape)
        }
        .frame(width: size.width, height: size.height)
    }

    // MARK: - Collapsed

    /// Two small wings hugging the physical notch. The middle is left empty because on a
    /// notched display there are no pixels there to draw into.
    private var collapsedContent: some View {
        let metrics = viewModel.metrics
        let thumb = metrics.notchHeight - 10

        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                ArtworkThumbnail(size: thumb)
                Spacer(minLength: 0)
            }
            // Clear of the inverted fillet where the shape meets the bezel.
            .padding(.leading, Theme.notchCornerRadius + 2)
            .frame(width: Theme.collapsedWingWidth)

            Spacer(minLength: 0)
                .frame(width: metrics.notchWidth)

            HStack(spacing: 0) {
                Spacer(minLength: 0)

                if timer.isActive {
                    CollapsedCountdown()
                } else if viewModel.showVisualizer {
                    VisualizerView(isPlaying: player.snapshot.isPlaying, accent: player.accent)
                }
            }
            .padding(.trailing, Theme.notchCornerRadius + 2)
            .frame(width: Theme.collapsedWingWidth)
        }
    }

    // MARK: - Expanded

    private var expandedContent: some View {
        VStack(spacing: 0) {
            header
                .frame(height: viewModel.metrics.notchHeight)

            Spacer(minLength: 0)

            Group {
                switch viewModel.tab {
                case .player:
                    playerBody
                        .transition(.opacity)
                case .focus:
                    FocusView(dialSize: 112, compact: true)
                        .transition(.opacity)
                }
            }
            .animation(.notchQuick, value: viewModel.tab)

            Spacer(minLength: 0)
        }
    }

    private var playerBody: some View {
        HStack(alignment: .center, spacing: artworkStyle == .cover ? 18 : 10) {
            DeckView(size: 124)

            VStack(alignment: .leading, spacing: 10) {
                TrackInfoView()
                    .contentShape(Rectangle())
                    .onTapGesture { player.openSourceApp() }
                ProgressBar()
                HStack {
                    TransportControls()
                    Spacer()
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

        let wingWidth = (Theme.expandedWidth - metrics.notchWidth) / 2

        return HStack(spacing: 0) {
            // The whole left wing is one button, so a click aimed at the collapsed pill's
            // little record still opens the music app after hover has expanded the panel.
            Button {
                player.openSourceApp()
            } label: {
                HStack(spacing: 5) {
                    Circle()
                        .fill(player.snapshot.isPlaying ? player.accent : Color.white.opacity(0.28))
                        .frame(width: 5, height: 5)

                    Text(player.snapshot.hasTrack
                         ? player.snapshot.provider.displayName
                         : "Spindle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.secondaryText)

                    Image(systemName: "arrow.up.forward")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundStyle(Theme.tertiaryText)

                    Spacer(minLength: 0)
                }
                .padding(.leading, 16)
                .frame(width: wingWidth, height: metrics.notchHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open \(player.sourceProvider.displayName)")

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

                ProviderPicker()

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

/// Record / timer toggle in the header.
private struct TabSwitcher: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 2) {
            tabButton(.player, symbol: "opticaldisc.fill", help: "Turntable")
            tabButton(.focus, symbol: "timer", help: "Focus timer")
        }
        .padding(2)
        .background(Capsule().fill(Color.white.opacity(0.08)))
    }

    private func tabButton(_ tab: NotchViewModel.Tab, symbol: String, help: String) -> some View {
        let selected = viewModel.tab == tab
        return Button {
            viewModel.tab = tab
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(selected ? Color.white : Theme.tertiaryText)
                // A running timer tints its tab so it's visible from the player side.
                .overlay(alignment: .topTrailing) {
                    if tab == .focus && timer.isRunning && !selected {
                        Circle().fill(timer.phase.color).frame(width: 4, height: 4).offset(x: 3, y: -2)
                    }
                }
                .frame(width: 22, height: 16)
                .background(Capsule().fill(Color.white.opacity(selected ? 0.18 : 0)))
        }
        .buttonStyle(.plain)
        .help(help)
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

/// Lets the user pin the display to one app instead of following whatever is playing.
private struct ProviderPicker: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        Menu {
            Button {
                player.pinnedProvider = nil
            } label: {
                // A checkmark in the title rather than a Label: an empty systemImage
                // still reserves an icon slot and knocks the titles out of alignment.
                Text(player.pinnedProvider == nil
                     ? "\u{2713} Follow whatever is playing"
                     : "Follow whatever is playing")
            }

            Divider()

            ForEach(ProviderID.allCases) { provider in
                Button {
                    player.pinnedProvider = provider
                } label: {
                    Text(player.pinnedProvider == provider
                         ? "\u{2713} \(provider.displayName)"
                         : provider.displayName)
                }
                .disabled(!player.availableProviders.contains(provider))
            }
        } label: {
            Image(systemName: "music.note.list")
                .font(.system(size: 11))
                .foregroundStyle(Theme.tertiaryText)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
