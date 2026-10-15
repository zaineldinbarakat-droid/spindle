import Foundation
import MenuBarVisibility

/// macOS 27's own way of hiding status items, as used by its exam ("assessment")
/// mode: Sleeve hands MenuBarAgent an allow-list of apps and macOS removes every
/// other app's icons and reflows the bar — so, unlike covering, hidden icons stop
/// taking up space.
///
/// This is a private API (see `MenuBarVisibility.h`). Everything about it is
/// resolved at runtime and fails open: if it's missing or errors, Sleeve releases
/// any restriction and falls back to covering, rather than leaving icons hidden.
///
/// Limits, all imposed by what macOS exposes:
/// - It works per app: an app's icons hide or show together.
/// - macOS's own items (clock, Wi-Fi, Control Center…) are passed as "system items"
///   and are always kept; Sleeve covers them instead when they're in a hidden section.
/// - An icon whose owner has no bundle identifier can't be allow-listed, so it is
///   hidden whenever any restriction is active.
@MainActor
final class NativeVisibility {
    /// Handle to an active restriction. Releasing it (or quitting) restores the bar.
    final class Restriction {
        fileprivate var raw: Any?
        let allowed: Set<String>

        fileprivate init(raw: Any, allowed: Set<String>) {
            self.raw = raw
            self.allowed = allowed
        }

        func release() {
            guard let raw else { return }
            self.raw = nil
            SLVMenuBarVisibilityInvalidate(raw)
        }

        deinit {
            if let raw { SLVMenuBarVisibilityInvalidate(raw) }
        }
    }

    /// macOS system item identifiers to keep. Unknown identifiers are ignored, so a
    /// generous range covers items this particular Mac doesn't have.
    private static let systemItemsToKeep: [NSNumber] = (0..<64).map { NSNumber(value: $0) }

    static var isAvailable: Bool { SLVMenuBarVisibilityIsAvailable() }

    /// Asks macOS to show only `allowed` apps' icons (plus system items).
    func restrict(to allowed: Set<String>) async -> Result<Restriction, Error> {
        await withCheckedContinuation { continuation in
            SLVMenuBarVisibilityActivate(Self.systemItemsToKeep, Array(allowed).sorted()) { raw, error in
                if let raw {
                    continuation.resume(returning: .success(Restriction(raw: raw, allowed: allowed)))
                } else {
                    continuation.resume(returning: .failure(error ?? NSError(domain: "SleeveMenuBarVisibility", code: 2)))
                }
            }
        }
    }
}
