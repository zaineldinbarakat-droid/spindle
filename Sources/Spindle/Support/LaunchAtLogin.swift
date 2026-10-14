import Foundation
import ServiceManagement

/// Thin wrapper over `SMAppService`, which is the supported replacement for the old
/// login-item APIs on macOS 13 and later.
enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func set(_ enabled: Bool) -> Bool {
        do {
            if enabled {
                // Throws if the app is still in a quarantined download location.
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return true
        } catch {
            NSLog("Spindle: could not change launch-at-login: \(error.localizedDescription)")
            return false
        }
    }
}
