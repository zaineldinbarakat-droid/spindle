import SwiftUI

/// Shared references to the long-lived objects.
///
/// The panel, the status-bar menu and the settings window are three separate AppKit
/// windows that all need the same `PlayerManager`; a single owner is simpler than
/// threading them through every construction site.
@MainActor
final class AppEnvironment {
    static let shared = AppEnvironment()

    let player = PlayerManager()
    let notch = NotchViewModel()

    private init() {}
}
