import AppKit

/// Self-update for Spindle and Sleeve, each from its own GitHub repository.
///
/// The repo carries `updates/latest.json` (the newest version and its notes) next to
/// a zip of the app. An app compares that version with its own; if it's newer, it
/// offers to download its zip, checks the download really is the same app with an
/// intact signature, swaps it in place of itself and relaunches.
///
/// Built so a broken-by-macOS-update app can be fixed remotely: fix, run
/// `./release.sh`, push — and both apps pick it up.
@MainActor
public final class Updater {
    /// `owner/name` of the repository the app is published from.
    public let repository: String
    private var rawBase: URL {
        URL(string: "https://raw.githubusercontent.com/\(repository)/main/")!
    }

    public struct Manifest: Decodable {
        public let version: String
        public let notes: String?
        public let minimumSystemVersion: String?
    }

    public enum UpdateError: LocalizedError {
        case badDownload, wrongApp, badSignature, notReplaceable
        public var errorDescription: String? {
            switch self {
            case .badDownload: return "The download didn't contain the app."
            case .wrongApp: return "The download was a different app, so it wasn't installed."
            case .badSignature: return "The download's code signature didn't check out, so it wasn't installed."
            case .notReplaceable: return "This copy of the app can't be replaced where it is. Move it to a folder you can write to."
            }
        }
    }

    private let appName: String
    private let defaults = UserDefaults.standard
    private var isChecking = false

    /// `appName` is both the bundle name and the zip name: `updates/<appName>.zip`.
    public init(appName: String, repository: String) {
        self.appName = appName
        self.repository = repository
    }

    public var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    public var checksAutomatically: Bool {
        get { defaults.object(forKey: "updatesCheckAutomatically") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "updatesCheckAutomatically") }
    }

    /// At launch: quietly, at most once a day; speaks up only if there's an update.
    public func checkInBackgroundIfDue() {
        guard checksAutomatically else { return }
        let last = defaults.object(forKey: "updatesLastCheck") as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 60 * 60 * 20 else { return }
        Task { await check(userInitiated: false) }
    }

    /// From the menu or Settings: always answers, even "you're up to date".
    public func checkNow() {
        Task { await check(userInitiated: true) }
    }

    private func check(userInitiated: Bool) async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }
        do {
            let manifest = try await fetchManifest()
            defaults.set(Date(), forKey: "updatesLastCheck")
            guard Self.isVersion(manifest.version, newerThan: currentVersion) else {
                if userInitiated { alert("\(appName) is up to date", "You have version \(currentVersion), the newest there is.") }
                return
            }
            if let minimum = manifest.minimumSystemVersion, !Self.systemIsAtLeast(minimum) {
                if userInitiated { alert("Update needs a newer macOS", "\(appName) \(manifest.version) needs macOS \(minimum) or later.") }
                return
            }
            offer(manifest)
        } catch {
            if userInitiated { alert("Couldn't check for updates", error.localizedDescription) }
        }
    }

    private func fetchManifest() async throws -> Manifest {
        var request = URLRequest(url: rawBase.appendingPathComponent("updates/latest.json"))
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Manifest.self, from: data)
    }

    private func offer(_ manifest: Manifest) {
        let alert = NSAlert()
        alert.messageText = "\(appName) \(manifest.version) is available"
        alert.informativeText = "You have \(currentVersion).\n\n" + (manifest.notes ?? "")
        alert.addButton(withTitle: "Install & Relaunch")
        alert.addButton(withTitle: "Later")
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task {
            do {
                try await install()
            } catch {
                self.alert("Update failed", error.localizedDescription)
            }
        }
    }

    // MARK: - Installing

    private func install() async throws {
        let zipURL = rawBase.appendingPathComponent("updates/\(appName).zip")
        let (downloaded, _) = try await URLSession.shared.download(from: zipURL)

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(appName)-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let zip = work.appendingPathComponent("\(appName).zip")
        try FileManager.default.moveItem(at: downloaded, to: zip)

        // Subprocesses run off the main thread: waiting on one spins the run loop,
        // which can re-enter SwiftUI mid-update.
        guard try await Self.run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path]) == 0 else {
            throw UpdateError.badDownload
        }
        let newApp = work.appendingPathComponent("\(appName).app")
        guard let info = NSDictionary(contentsOf: newApp.appendingPathComponent("Contents/Info.plist")) else {
            throw UpdateError.badDownload
        }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongApp
        }
        guard try await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", newApp.path]) == 0 else {
            throw UpdateError.badSignature
        }

        let current = Bundle.main.bundleURL
        guard FileManager.default.isWritableFile(atPath: current.deletingLastPathComponent().path) else {
            throw UpdateError.notReplaceable
        }
        // Once this app has quit: set the old copy aside (not deleted, in case), put
        // the new one in its place, and open it.
        let aside = work.appendingPathComponent("previous-\(appName).app")
        let script = """
        while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
        /bin/mv "$1" "$2" && /bin/mv "$3" "$1" && /usr/bin/open "$1"
        """
        let swap = Process()
        swap.executableURL = URL(fileURLWithPath: "/bin/sh")
        swap.arguments = ["-c", script, "sh", current.path, aside.path, newApp.path]
        try swap.run()
        NSApp.terminate(nil)
    }

    private static func run(_ tool: String, _ arguments: [String]) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: tool)
                process.arguments = arguments
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                do {
                    try process.run()
                    process.waitUntilExit()
                    continuation.resume(returning: process.terminationStatus)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Helpers

    private func alert(_ title: String, _ message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    /// "0.10.0" > "0.9.1": compares numerically, component by component.
    public static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    private static func systemIsAtLeast(_ version: String) -> Bool {
        let parts = version.split(separator: ".").map { Int($0) ?? 0 }
        let required = OperatingSystemVersion(majorVersion: parts.first ?? 0,
                                              minorVersion: parts.count > 1 ? parts[1] : 0,
                                              patchVersion: parts.count > 2 ? parts[2] : 0)
        return ProcessInfo.processInfo.isOperatingSystemAtLeast(required)
    }
}
