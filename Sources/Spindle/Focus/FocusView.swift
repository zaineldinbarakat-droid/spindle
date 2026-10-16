import SwiftUI

/// The focus timer as it appears in the expanded notch: a kitchen-timer dial on the
/// left where the turntable usually sits, controls and a little now-playing strip on
/// the right so the music never disappears from view.
struct FocusView: View {
    @EnvironmentObject private var timer: PomodoroTimer
    @EnvironmentObject private var player: PlayerManager

    var dialSize: CGFloat = 168
    /// Tighter type and spacing for the notch.
    var compact = false

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 24 : 22) {
            FocusDial(size: dialSize)
                .frame(width: dialSize * (compact ? 1.2 : 1.55), height: dialSize * 1.12)

            VStack(alignment: .leading, spacing: compact ? 8 : 12) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Image(systemName: timer.phase.symbol)
                        Text(timer.phase.title.uppercased())
                            .kerning(1.2)
                    }
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(timer.phase.color)

                    Text(timer.remainingString)
                        .font(.system(size: compact ? 32 : 40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryText)
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.notchQuick, value: timer.remainingString)
                }

                SessionDots()

                FocusControls()

                if !compact {
                    MiniNowPlaying()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 22)
        }
        .padding(.leading, compact ? 20 : 14)
    }
}

/// Retro kitchen timer: a cream face with minute ticks and a coloured wedge that
/// shrinks as the phase runs out.
struct FocusDial: View {
    @EnvironmentObject private var timer: PomodoroTimer
    var size: CGFloat

    var body: some View {
        ZStack {
            // Bezel.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.32), Color(white: 0.12)],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size * 1.06, height: size * 1.06)
                .shadow(color: .black.opacity(0.6), radius: size * 0.06, y: size * 0.03)

            // Face.
            Circle()
                .fill(RadialGradient(colors: [Theme.cream, Theme.cream.opacity(0.82)],
                                     center: .init(x: 0.4, y: 0.35),
                                     startRadius: 0, endRadius: size * 0.6))
                .frame(width: size, height: size)

            // Remaining time wedge.
            RemainingWedge(fraction: 1 - timer.progress)
                .fill(timer.phase.color.opacity(0.88))
                .frame(width: size * 0.84, height: size * 0.84)
                .animation(.linear(duration: 0.9), value: timer.progress)

            DialTicks()
                .frame(width: size * 0.94, height: size * 0.94)

            // Knob.
            Circle()
                .fill(LinearGradient(colors: [Color(white: 0.95), Color(white: 0.7)],
                                     startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.2, height: size * 0.2)
                .overlay(
                    Capsule()
                        .fill(Color(white: 0.55))
                        .frame(width: size * 0.03, height: size * 0.16)
                )
                .rotationEffect(.degrees(-360 * (1 - timer.progress)))
                .shadow(color: .black.opacity(0.35), radius: 3, y: 2)
        }
        .contentShape(Circle())
        .onTapGesture { timer.toggle() }
        .help(timer.isRunning ? "Pause" : "Start")
    }
}

/// A pie slice starting at 12 o'clock and running clockwise.
struct RemainingWedge: Shape {
    var fraction: Double

    var animatableData: Double {
        get { fraction }
        set { fraction = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard fraction > 0.0005 else { return path }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.move(to: center)
        path.addArc(center: center,
                    radius: radius,
                    startAngle: .degrees(-90),
                    endAngle: .degrees(-90 + 360 * min(fraction, 1)),
                    clockwise: false)
        path.closeSubpath()
        return path
    }
}

/// Sixty ticks, every fifth one long — the face of every kitchen timer ever made.
private struct DialTicks: View {
    var body: some View {
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2
            for index in 0..<60 {
                let major = index % 5 == 0
                let angle = Double(index) / 60 * 2 * .pi - .pi / 2
                let inner = radius * (major ? 0.84 : 0.91)
                var tick = Path()
                tick.move(to: CGPoint(x: center.x + cos(angle) * inner,
                                      y: center.y + sin(angle) * inner))
                tick.addLine(to: CGPoint(x: center.x + cos(angle) * radius,
                                         y: center.y + sin(angle) * radius))
                context.stroke(tick,
                               with: .color(Color.black.opacity(major ? 0.7 : 0.35)),
                               lineWidth: major ? 1.6 : 0.8)
            }
        }
    }
}

struct SessionDots: View {
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<max(timer.sessionsBeforeLongBreak, 1), id: \.self) { index in
                Circle()
                    .fill(index < timer.sessionInSet ? Theme.focusColor : Color.white.opacity(0.16))
                    .frame(width: 7, height: 7)
            }
            Text("\(timer.completedSessions) done")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.tertiaryText)
                .padding(.leading, 4)
        }
    }
}

struct FocusControls: View {
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 10) {
            Button {
                timer.toggle()
            } label: {
                Label(timer.isRunning ? "Pause" : (timer.isPaused ? "Resume" : "Start"),
                      systemImage: timer.isRunning ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(Capsule().fill(timer.phase.color.opacity(0.9)))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            PresetMenu()

            IconButton(symbol: "forward.end.fill", help: "Skip to next phase") { timer.skip() }
            IconButton(symbol: "arrow.counterclockwise", help: "Reset") { timer.reset() }
        }
    }
}

/// One tap between the two timings: 25/5 and 50/10. The active one is lit; tapping
/// the other switches straight away, no trip to Settings.
private struct PresetMenu: View {
    @EnvironmentObject private var timer: PomodoroTimer

    var body: some View {
        HStack(spacing: 2) {
            ForEach(PomodoroTimer.Preset.all) { preset in
                let selected = timer.currentPreset == preset
                Button {
                    withAnimation(.notchQuick) { timer.apply(preset) }
                } label: {
                    Text("\(preset.focus)/\(preset.shortBreak)")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(selected ? Color.black : Theme.secondaryText)
                        .padding(.horizontal, 9)
                        .frame(height: 24)
                        .background(Capsule().fill(selected ? Color.white : Color.clear))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(preset.name)
            }
        }
        .padding(3)
        .background(Capsule().fill(Color.white.opacity(0.1)))
    }
}

private struct IconButton: View {
    var symbol: String
    var help: String
    var action: () -> Void
    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Theme.primaryText)
                .frame(width: 30, height: 30)
                .background(Circle().fill(Color.white.opacity(isHovering ? 0.16 : 0.08)))
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
    }
}

/// One line of "what's playing" with a tiny spinning record, so the focus tab still
/// feels like part of the turntable.
private struct MiniNowPlaying: View {
    @EnvironmentObject private var player: PlayerManager

    var body: some View {
        HStack(spacing: 8) {
            VinylView(artwork: player.artwork,
                      accent: player.accent,
                      isSpinning: player.snapshot.isPlaying)
                .frame(width: 22, height: 22)
                .onTapGesture { player.openSourceApp() }

            Text(player.snapshot.hasTrack
                 ? "\(player.snapshot.title) · \(player.snapshot.artist)"
                 : "Nothing playing")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                player.togglePlayPause()
            } label: {
                Image(systemName: player.snapshot.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.secondaryText)
            }
            .buttonStyle(.plain)
            .disabled(!player.snapshot.hasTrack)
        }
    }
}
