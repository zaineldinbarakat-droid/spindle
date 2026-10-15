import SwiftUI

/// "Version 0.3.0 · Check for Updates…" plus the automatic-check switch, for both
/// apps' Settings.
public struct UpdatesRow: View {
    let updater: Updater
    @State private var automatic: Bool

    public init(updater: Updater) {
        self.updater = updater
        _automatic = State(initialValue: updater.checksAutomatically)
    }

    public var body: some View {
        HStack {
            Text("Version \(updater.currentVersion)")
            Spacer()
            Button("Check for Updates…") { updater.checkNow() }
        }
        Toggle("Check for updates automatically", isOn: $automatic)
            .onChange(of: automatic) { _, on in updater.checksAutomatically = on }
    }
}
