import SwiftUI

/// The one-time tip that stops Sleeve's icon jumping about.
struct PlacementTipView: View {
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Keep this icon still").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "command").font(.title2).frame(width: 28)
                Text("Hold **⌘** and drag this icon to the **right**, next to Control Center and the clock. Your apps will then appear to its left, and it won't move when they come and go.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("macOS doesn't let apps place their own icons, so this one drag has to be yours. macOS remembers it.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Got it", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 320)
    }
}
