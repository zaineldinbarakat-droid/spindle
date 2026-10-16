import AppKit
import Combine
import SpindleSync

/// Sleeve's end of the Spindle sync channel.
@MainActor
final class SpindleBridge: ObservableObject {
    /// Last state Spindle published, or nil if it isn't running.
    @Published private(set) var state: SpindleState?

    var isSpindleRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: SyncChannel.spindleBundleID).isEmpty
    }

    /// Spindle's panel opened: close anything of ours that would overlap it.
    var onSpindleExpanded: (() -> Void)?

    private var observers: [NSObjectProtocol] = []

    init() {
        observers.append(SyncChannel.observe(SyncChannel.spindleState) { [weak self] info in
            Task { @MainActor in
                guard let self, let new = SpindleState(userInfo: info) else { return }
                let opened = new.isExpanded && self.state?.isExpanded != true
                self.state = new
                if opened { self.onSpindleExpanded?() }
            }
        })
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SyncChannel.spindleBundleID else { return }
            Task { @MainActor in self?.state = nil }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main
        ) { note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard app?.bundleIdentifier == SyncChannel.spindleBundleID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                SyncChannel.post(SyncChannel.requestSpindleState)
            }
        }
        SyncChannel.post(SyncChannel.requestSpindleState)
    }

    /// True if `point` is somewhere Spindle handles itself: its notch pill, the zone
    /// that opens it, or — while open — the whole panel. A margin keeps the two apps
    /// from both reacting when the cursor brushes the boundary.
    func owns(_ point: CGPoint) -> Bool {
        guard let state, SleeveSettings.shared.avoidSpindle else { return false }
        // Inclusive of the very top edge, where the cursor reports y == screen maxY.
        func inside(_ rect: CGRect, margin: CGFloat) -> Bool {
            guard !rect.isEmpty else { return false }
            let r = rect.insetBy(dx: -margin, dy: -margin)
            return point.x >= r.minX && point.x <= r.maxX && point.y >= r.minY && point.y <= r.maxY + 8
        }
        return inside(state.hoverZone, margin: 10)
            || inside(state.pillFrame, margin: 10)
            || inside(state.panelFrame, margin: 6)
    }

    func sleeveBarChanged(open: Bool) {
        SyncChannel.post(SyncChannel.sleeveBar, ["open": open])
    }

    func zenChanged(_ enabled: Bool) {
        let hide = enabled && SleeveSettings.shared.zenHidesSpindle
        SyncChannel.post(SyncChannel.zenMode, ["enabled": hide])
    }

    func sleeveTerminating() {
        SyncChannel.post(SyncChannel.sleeveTerminated)
    }
}
