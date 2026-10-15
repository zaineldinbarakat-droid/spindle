import AppKit
import CoreLocation
import CoreWLAN
import IOKit.ps

/// "Show my hidden icons when …"
struct TriggerRule: Codable, Identifiable, Equatable {
    enum Condition: Codable, Equatable {
        case batteryBelow(percent: Int)
        case wifiNetwork(ssid: String)
        case focusActive
        /// Runs the script; exit status 0 means "condition met".
        case script(path: String)

        var title: String {
            switch self {
            case .batteryBelow(let p): return "Battery below \(p)%"
            case .wifiNetwork(let ssid): return ssid.isEmpty ? "Connected to a Wi-Fi network" : "Connected to “\(ssid)”"
            case .focusActive: return "A Focus mode is on"
            case .script(let path): return "Script succeeds: \((path as NSString).lastPathComponent)"
            }
        }
    }

    enum Action: String, Codable, CaseIterable, Identifiable {
        case showHidden, showAll
        var id: String { rawValue }
        var title: String { self == .showHidden ? "Show Hidden section" : "Show everything" }
    }

    var id = UUID()
    var condition: Condition
    var action: Action = .showHidden
    var isEnabled = true
}

/// Evaluates rules and pins the reveal open while any of them holds.
@MainActor
final class AutomationEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// IDs of rules whose condition is currently true; shown live in Settings.
    @Published private(set) var activeRuleIDs: Set<UUID> = []
    @Published private(set) var wifiNeedsLocation = false
    @Published private(set) var focusNeedsFullDiskAccess = false

    private unowned let sections: SectionManager
    private let settings = SleeveSettings.shared
    private var timer: Timer?
    private var powerSource: CFRunLoopSource?
    private let locationManager = CLLocationManager()
    private var lastScriptResults: [UUID: Bool] = [:]

    init(sections: SectionManager) {
        self.sections = sections
        super.init()
        locationManager.delegate = self

        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.evaluate() }
        }
        // Battery changes arrive as they happen rather than on the next tick.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let engine = Unmanaged<AutomationEngine>.fromOpaque(context).takeUnretainedValue()
            Task { @MainActor in engine.evaluate() }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
        evaluate()
    }

    func evaluate() {
        let rules = settings.rules.filter(\.isEnabled)
        if rules.contains(where: { if case .wifiNetwork = $0.condition { return true }; return false }) {
            requestLocationIfNeeded()
        }

        var active = Set<UUID>()
        var pin: SectionManager.RevealState?
        for rule in rules where isMet(rule) {
            active.insert(rule.id)
            if rule.action == .showAll { pin = .all } else if pin == nil { pin = .hidden }
        }
        activeRuleIDs = active
        if sections.pinnedByRule != pin { sections.applyRulePin(pin) }
    }

    private func isMet(_ rule: TriggerRule) -> Bool {
        switch rule.condition {
        case .batteryBelow(let percent):
            guard let level = Self.batteryLevel() else { return false }
            return level < percent
        case .wifiNetwork(let ssid):
            guard let current = CWWiFiClient.shared().interface()?.ssid() else {
                // macOS hides the SSID from apps without Location access.
                wifiNeedsLocation = locationManager.authorizationStatus != .authorizedAlways
                return false
            }
            wifiNeedsLocation = false
            return ssid.isEmpty || current == ssid
        case .focusActive:
            return isFocusActive()
        case .script(let path):
            runScript(path, for: rule.id)
            return lastScriptResults[rule.id] ?? false
        }
    }

    static func batteryLevel() -> Int? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef] else { return nil }
        for source in list {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  let current = description[kIOPSCurrentCapacityKey] as? Int,
                  let max = description[kIOPSMaxCapacityKey] as? Int, max > 0 else { continue }
            return current * 100 / max
        }
        return nil
    }

    /// There is no public Focus API. Focus state is recorded in this file, which macOS
    /// only lets apps with Full Disk Access read.
    private func isFocusActive() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/DoNotDisturb/DB/Assertions.json")
        guard let data = try? Data(contentsOf: url) else {
            focusNeedsFullDiskAccess = true
            return false
        }
        focusNeedsFullDiskAccess = false
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entries = json["data"] as? [[String: Any]] else { return false }
        return entries.contains { entry in
            ((entry["storeAssertionRecords"] as? [Any])?.isEmpty == false)
        }
    }

    /// Scripts run off the main thread with a time limit; the result lands on the
    /// next evaluation.
    private func runScript(_ path: String, for id: UUID) {
        guard !path.isEmpty else { return }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", "\"$0\"", path]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            var ok = false
            if (try? process.run()) != nil {
                let deadline = Date().addingTimeInterval(10)
                while process.isRunning && Date() < deadline { usleep(50_000) }
                if process.isRunning { process.terminate() } else { ok = process.terminationStatus == 0 }
            }
            Task { @MainActor in
                guard let self else { return }
                let changed = self.lastScriptResults[id] != ok
                self.lastScriptResults[id] = ok
                if changed { self.evaluate() }
            }
        }
    }

    private var askedForLocation = false

    private func requestLocationIfNeeded() {
        guard !askedForLocation, locationManager.authorizationStatus == .notDetermined else { return }
        askedForLocation = true
        locationManager.requestAlwaysAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in self.evaluate() }
    }
}
