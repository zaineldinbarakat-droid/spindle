import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var player: PlayerManager
    @EnvironmentObject private var notch: NotchViewModel

    @State private var launchAtLogin = LaunchAtLogin.isEnabled

    var body: some View {
        Form {
            Section("Behaviour") {
                Toggle("Open when the cursor reaches the notch", isOn: $notch.openOnHover)
                Toggle("Show visualizer in the collapsed view", isOn: $notch.showVisualizer)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        // Re-read: registration can fail (e.g. quarantined app).
                        if !LaunchAtLogin.set(enabled) {
                            launchAtLogin = LaunchAtLogin.isEnabled
                        }
                    }
            }

            Section("Music source") {
                Picker("Follow", selection: Binding(
                    get: { player.pinnedProvider },
                    set: { player.pinnedProvider = $0 }
                )) {
                    Text("Whatever is playing").tag(ProviderID?.none)
                    ForEach(ProviderID.allCases) { provider in
                        Text(provider.displayName).tag(ProviderID?.some(provider))
                    }
                }
                .pickerStyle(.radioGroup)

                if !player.deniedProviders.isEmpty {
                    let names = player.deniedProviders.map(\.displayName).sorted().joined(separator: ", ")
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Spindle can't control \(names).")
                                .font(.callout)
                            Button("Open Automation Settings") {
                                player.openAutomationSettings()
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            Section {
                Text("Spindle reads and controls Music and Spotify through Apple Events. "
                     + "It never connects to a streaming service itself, so nothing leaves this Mac.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 330)
    }
}
