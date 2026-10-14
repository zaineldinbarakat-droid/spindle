import SwiftUI

struct NotchRootView: View {
    @EnvironmentObject private var viewModel: NotchViewModel
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        ZStack(alignment: .top) {
            // The window is always full expanded size; this keeps it invisible and
            // click-through everywhere the panel isn't actually drawn.
            Color.clear

            if viewModel.isExpanded {
                expandedPanel
                    .transition(.notchReveal)
            } else if player.snapshot.hasTrack {
                collapsedPill
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }

    // MARK: - Collapsed

    /// Two small wings hugging the physical notch. The middle is left empty because on a
    /// notched display there are no pixels there to draw into.
    private var collapsedPill: some View {
        let metrics = viewModel.metrics
        let height = metrics.notchHeight

        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                VinylView(artwork: player.artwork,
                          accent: player.accent,
                          isSpinning: player.snapshot.isPlaying)
                    .frame(width: height - 9, height: height - 9)

                Spacer(minLength: 0)
            }
            .frame(width: Theme.collapsedWingWidth)
            .padding(.leading, 8)

            Spacer(minLength: 0)
                .frame(width: metrics.notchWidth)

            HStack(spacing: 6) {
                Spacer(minLength: 0)

                if viewModel.showVisualizer {
                    VisualizerView(isPlaying: player.snapshot.isPlaying, accent: player.accent)
                }
            }
            .frame(width: Theme.collapsedWingWidth)
            .padding(.trailing, 10)
        }
        .frame(width: metrics.notchWidth + Theme.collapsedWingWidth * 2, height: height)
        .background(
            NotchShape(topRadius: Theme.notchCornerRadius, bottomRadius: Theme.notchCornerRadius)
                .fill(Theme.panel)
        )
    }

    // MARK: - Expanded

    private var expandedPanel: some View {
        let metrics = viewModel.metrics

        return VStack(spacing: 0) {
            header
                .frame(height: metrics.notchHeight)

            HStack(alignment: .center, spacing: 14) {
                TurntableView(diameter: 168)
                    .frame(width: 168 * 1.55, height: 168 * 1.18)

                VStack(alignment: .leading, spacing: 12) {
                    TrackInfoView()
                    ProgressBar()
                    HStack {
                        TransportControls()
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.trailing, 22)
            }
            .padding(.leading, 14)

            Spacer(minLength: 0)
        }
        .frame(width: Theme.expandedWidth, height: Theme.expandedHeight)
        .background(
            NotchShape()
                .fill(Theme.panel)
                .overlay(
                    // Cover art bleeding a faint glow into the panel.
                    NotchShape()
                        .fill(
                            RadialGradient(colors: [player.accent.opacity(0.22), .clear],
                                           center: .init(x: 0.22, y: 0.55),
                                           startRadius: 10,
                                           endRadius: 340)
                        )
                )
                .shadow(color: .black.opacity(0.55), radius: 22, y: 10)
        )
        .clipShape(NotchShape())
    }

    /// Sits in the strip beside the notch: provider on the left, controls on the right.
    private var header: some View {
        let metrics = viewModel.metrics

        return HStack(spacing: 0) {
            HStack(spacing: 5) {
                Circle()
                    .fill(player.snapshot.isPlaying ? player.accent : Color.white.opacity(0.28))
                    .frame(width: 5, height: 5)

                Text(player.snapshot.hasTrack
                     ? player.snapshot.provider.displayName
                     : "Spindle")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.leading, 16)

            Spacer(minLength: metrics.notchWidth)

            HStack(spacing: 10) {
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
