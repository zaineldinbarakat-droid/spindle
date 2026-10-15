import SwiftUI

/// Shown when the toggle is clicked but nothing is hidden yet — the moment a new user
/// most needs to know how sections work.
struct HowToHideView: View {
    var close: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Nothing is hidden yet").font(.headline)
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "command").font(.title2).frame(width: 28)
                Text("Hold **⌘** and drag a menu bar icon to the **left of the faint │ marks** next to Sleeve's icon.")
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "eye.slash").font(.title2).frame(width: 28)
                Text("Icons left of the first │ are **Hidden**; left of the second │ are **Always Hidden**. Click Sleeve's icon to show or hide them.")
            }
            HStack {
                Button("Open Layout Settings") {
                    close()
                    SleeveSettingsWindow.show(tab: .layout)
                }
                Spacer()
                Button("Got it", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12))
        .padding(16)
        .frame(width: 330)
    }
}
