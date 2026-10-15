import AppKit
import ApplicationServices

/// Getting (and keeping) the Accessibility grant.
///
/// The usual failure: System Settings lists Sleeve with the switch on, but the entry
/// was recorded for an earlier build whose code signature no longer matches, so macOS
/// still treats Sleeve as untrusted — and flipping that switch doesn't refresh it.
/// The only reliable cure is to delete Sleeve's entry and grant again, which is what
/// `fix()` does. (Builds are now signed with a stable requirement, so it should only
/// ever be needed once.)
@MainActor
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Shows the system prompt, which also adds a fresh entry for this build.
    static func request() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    static func openSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    /// Clears Sleeve's own Accessibility entry (only Sleeve's — `tccutil` is given our
    /// bundle identifier), then asks again so a correct entry is created.
    static func fix() {
        guard let bundleID = Bundle.main.bundleIdentifier else { return request() }
        DispatchQueue.global(qos: .userInitiated).async {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
            process.arguments = ["reset", "Accessibility", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try? process.run()
            process.waitUntilExit()
            DispatchQueue.main.async {
                request()
                openSettings()
            }
        }
    }
}
