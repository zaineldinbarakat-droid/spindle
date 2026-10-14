import Foundation
import AppKit

/// Runs AppleScript against the media apps.
///
/// Everything is funnelled through one serial queue because `NSAppleScript` wants to be
/// used from the thread that created it, and because we never want two polls in flight.
final class AppleScriptBridge: @unchecked Sendable {
    static let shared = AppleScriptBridge()

    private let queue = DispatchQueue(label: "com.spindle.applescript", qos: .userInitiated)
    private var compiled: [String: NSAppleScript] = [:]

    private init() {}

    // MARK: - Authorization

    /// Apple Event error codes that mean "the user has not said yes (yet)".
    private static let permissionDeniedCodes: Set<Int> = [-1743, -1744, -10004]
    /// Codes that mean the target app simply isn't there to talk to.
    private static let targetMissingCodes: Set<Int> = [-600, -609, -1728]

    /// Asks the Apple Events subsystem whether we may talk to `bundleID`, prompting the
    /// user the first time. Returning `true` only means the prompt was answered "OK".
    func requestAuthorization(for provider: ProviderID, prompt: Bool = true) -> Bool {
        var target = AEAddressDesc()
        let bundleID = provider.bundleIdentifier
        let created: OSErr = bundleID.withCString { cString in
            AECreateDesc(typeApplicationBundleID,
                         cString,
                         strlen(cString),
                         &target)
        }
        guard created == noErr else { return false }
        defer { AEDisposeDesc(&target) }
        let status = AEDeterminePermissionToAutomateTarget(&target, typeWildCard, typeWildCard, prompt)
        return status == noErr
    }

    func authorizationStatus(for provider: ProviderID) -> Bool {
        requestAuthorization(for: provider, prompt: false)
    }

    // MARK: - Running apps

    func isRunning(_ provider: ProviderID) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: provider.bundleIdentifier).isEmpty
    }

    // MARK: - Execution

    /// Synchronously evaluates `source`. Must not be called from the main thread for
    /// anything that can block (i.e. anything that talks to another process).
    func run(_ source: String, cacheKey: String? = nil) throws -> NSAppleEventDescriptor {
        try queue.sync {
            let script: NSAppleScript
            if let key = cacheKey, let existing = compiled[key] {
                script = existing
            } else {
                guard let fresh = NSAppleScript(source: source) else {
                    throw PlayerError.scriptFailed("Could not compile script.")
                }
                if let key = cacheKey { compiled[key] = fresh }
                script = fresh
            }

            var errorInfo: NSDictionary?
            let result = script.executeAndReturnError(&errorInfo)

            if let errorInfo {
                let code = (errorInfo[NSAppleScript.errorNumber] as? Int) ?? 0
                let message = (errorInfo[NSAppleScript.errorMessage] as? String) ?? "Unknown AppleScript error."
                if Self.permissionDeniedCodes.contains(code) {
                    throw PlayerError.scriptFailed("permission:\(code)")
                }
                if Self.targetMissingCodes.contains(code) {
                    throw PlayerError.scriptFailed("missing:\(code)")
                }
                throw PlayerError.scriptFailed(message)
            }
            return result
        }
    }

    /// Fire-and-forget: transport commands whose result we don't care about.
    func perform(_ source: String, cacheKey: String? = nil) {
        queue.async { [weak self] in
            _ = try? self?.run(source, cacheKey: cacheKey)
        }
    }

    /// Classifies an error thrown by `run` into something the UI can act on.
    static func classify(_ error: Error, provider: ProviderID) -> PlayerError {
        guard case PlayerError.scriptFailed(let message) = error else {
            return .scriptFailed(String(describing: error))
        }
        if message.hasPrefix("permission:") { return .notAuthorized(provider) }
        if message.hasPrefix("missing:") { return .notRunning(provider) }
        return .scriptFailed(message)
    }
}

// MARK: - Descriptor helpers

extension NSAppleEventDescriptor {
    /// Splits a delimiter-joined string result into fields.
    ///
    /// We ask the scripts to return one string rather than a list so that numbers,
    /// missing values and unicode titles all survive the trip intact.
    func fields(separatedBy separator: String) -> [String] {
        (stringValue ?? "").components(separatedBy: separator)
    }
}
