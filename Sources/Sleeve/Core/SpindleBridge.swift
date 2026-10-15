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

    /// True if `point` is somewhere Spindle handles itself.
    func owns(_ point: CGPoint) -> Bool {
        guard let state, SleeveSettings.shared.avoidSpindle else { return false }
        return state.hoverZone.insetBy(dx: -4, dy: -4).contains(point)
            || state.pillFrame.insetBy(dx: -4, dy: -4).contains(point)
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
