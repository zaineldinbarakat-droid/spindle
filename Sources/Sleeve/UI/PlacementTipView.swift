import SwiftUI

/// The one-time tip that stops Sleeve's icon jumping about.
struct PlacementTipView: View {
    /// The icon is in its fixed spot beside the notch rather than with the apps.
    var isFixed = false
    var putOnRight: () -> Void = {}
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(isFixed ? "Sleeve's icon is beside the notch" : "Put this icon on the right").font(.headline)
            if isFixed {
                Text("It never moves there, and your apps appear to its right. To have it on the right instead, beside Wi-Fi, switch it over — then ⌘-drag it into place once.")
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "command").font(.title2).frame(width: 28)
                    Text("With your apps showing, hold **⌘** and drag this icon to the **right of all of them**, next to Wi-Fi. They'll then appear to its left, and it won't move when they come and go.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text("macOS doesn't let apps place their own icons, so this one drag has to be yours. If macOS ever moves it back, Sleeve will remind you.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Spacer()
                if isFixed {
                    Button("Not Now", action: close)
                    Button("Put It on the Right") { putOnRight(); close() }.keyboardShortcut(.defaultAction)
                } else {
                    Button("Got it", action: close).keyboardShortcut(.defaultAction)
                }
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 320)
    }
}
