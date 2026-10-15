import AppKit

/// Status item spacing, via the same per-host global defaults the system reads.
///
/// macOS only picks the values up when an app creates its status items, so changes
/// take effect after the apps that own menu bar icons are relaunched.
enum MenuBarSpacing {
    private static let spacingKey = "NSStatusItemSpacing"
    private static let paddingKey = "NSStatusItemSelectionPadding"

    /// Current spacing, or nil when the system default is in use.
    ///
    /// Read and written through CFPreferences rather than by running `defaults`:
    /// waiting on a subprocess spins the run loop, and doing that while SwiftUI is
    /// building a view re-enters its update and aborts the app.
    static var current: Int? {
        CFPreferencesCopyValue(spacingKey as CFString, kCFPreferencesAnyApplication,
                               kCFPreferencesCurrentUser, kCFPreferencesCurrentHost) as? Int
    }

    static func set(_ value: Int?) {
        func write(_ key: String, _ number: Int?) {
            CFPreferencesSetValue(key as CFString, number.map { $0 as CFNumber },
                                  kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
        }
        write(spacingKey, value)
        // Keep the click target in proportion, or icons become hard to hit.
        write(paddingKey, value.map { max($0 / 2, 2) })
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesCurrentHost)
    }

    /// Apps that own at least one menu bar icon — what has to restart to see a change.
    static func appsToRelaunch(from items: [MenuBarItem]) -> [NSRunningApplication] {
        let own = ProcessInfo.processInfo.processIdentifier
        var seen = Set<pid_t>()
        return items.compactMap { item in
            guard item.pid != own, seen.insert(item.pid).inserted else { return nil }
            return NSRunningApplication(processIdentifier: item.pid)
        }
    }

    /// Quits and reopens each app. System agents (MenuBarAgent, Control Center…) are
    /// relaunched by launchd as soon as they exit.
    static func relaunch(_ apps: [NSRunningApplication]) {
        for app in apps {
            let url = app.bundleURL
            let isAgent = app.bundleIdentifier?.hasPrefix("com.apple.") == true
            // Agents ignore a polite quit; launchd brings them straight back.
            if isAgent { app.forceTerminate() } else { app.terminate() }
            guard !isAgent, let url else { continue }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.openApplication(at: url, configuration: config)
            }
        }
    }
}
