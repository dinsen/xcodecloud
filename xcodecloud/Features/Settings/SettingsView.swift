import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BuildFeedStore.self) private var buildFeedStore

    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshIntervalSeconds") private var autoRefreshIntervalSeconds: Double = 60
    @AppStorage("selectedAppDisplayName") private var selectedAppDisplayName = "Not selected"

    var body: some View {
        Form {
            Section("App Store Connect API") {
                NavigationLink {
                    CredentialsView()
                } label: {
                    HStack {
                        Image(systemName: "key.fill")
                            .foregroundStyle(.secondary)
                        Text("Credentials")
                        Spacer()
                        Text(buildFeedStore.hasCompleteCredentials ? "Configured" : "Missing")
                            .foregroundStyle(buildFeedStore.hasCompleteCredentials ? .green : .secondary)
                    }
                }
                .accessibilityIdentifier("settings-credentials-link")
            }

            Section("Refresh") {
                Toggle("Auto Refresh", isOn: $autoRefreshEnabled)

                HStack {
                    Text("Interval")
                    Spacer()
                    Text("\(Int(autoRefreshIntervalSeconds))s")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                Slider(
                    value: $autoRefreshIntervalSeconds,
                    in: 30...300,
                    step: 15
                )
                .disabled(!autoRefreshEnabled)
            }

            Section("Monitored App") {
                HStack {
                    Image(systemName: "app.badge")
                        .foregroundStyle(.secondary)
                    Text(selectedAppDisplayName)
                    Spacer()
                    Text("Coming Soon")
                        .foregroundStyle(.secondary)
                }

                Text("App search and selection is the next step after credentials setup.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
#if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
#endif
    }
}

#Preview {
    NavigationStack {
        SettingsView()
            .environment(BuildFeedStore())
    }
}
