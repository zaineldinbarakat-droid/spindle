import SwiftUI

/// Shared references to the long-lived objects.
///
/// The panel, the status-bar menu, the desktop windows and the settings window are
/// separate AppKit windows that all need the same `PlayerManager`; a single owner is
/// simpler than threading them through every construction site.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let player: PlayerManager
    let notch = NotchViewModel()
    let timer: PomodoroTimer
    let desktop: DesktopController

    private init() {
        let player = PlayerManager()
        let timer = PomodoroTimer(player: player)
        self.player = player
        self.timer = timer
        self.desktop = DesktopController(player: player, timer: timer)
    }
}
