import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BuildFeedStore.self) private var buildFeedStore

    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshIntervalSeconds") private var autoRefreshIntervalSeconds: Double = 60

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
                NavigationLink {
                    AppSelectionView()
                } label: {
                    HStack {
                        Image(systemName: "app.badge")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Selected App")
                            Text(buildFeedStore.monitoredAppDescription)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityIdentifier("settings-app-selection-link")

                if let appSelectionMessage = buildFeedStore.appSelectionMessage {
                    Text(appSelectionMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Select an app first. Dashboard and all Xcode Cloud actions unlock after selection.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Xcode Cloud") {
                NavigationLink {
                    WorkflowManagementView()
                } label: {
                    HStack {
                        Image(systemName: "slider.horizontal.3")
                            .foregroundStyle(.secondary)
                        Text("Workflows")
                    }
                }
                .disabled(!buildFeedStore.hasCompleteCredentials)

                NavigationLink {
                    CompatibilityAdvisorView()
                } label: {
                    HStack {
                        Image(systemName: "desktopcomputer")
                            .foregroundStyle(.secondary)
                        Text("Compatibility")
                    }
                }
                .disabled(!buildFeedStore.hasCompleteCredentials)

                NavigationLink {
                    RepositoryTopologyView()
                } label: {
                    HStack {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundStyle(.secondary)
                        Text("Repositories")
                    }
                }
                .disabled(!buildFeedStore.hasCompleteCredentials)
            }
        }
        .navigationTitle("Settings")
        .task {
            if buildFeedStore.hasCompleteCredentials && buildFeedStore.availableApps.isEmpty {
                await buildFeedStore.loadApps()
            }
        }
        .onChange(of: autoRefreshEnabled) { _, isEnabled in
            buildFeedStore.configureAutoRefresh(
                enabled: isEnabled,
                intervalSeconds: autoRefreshIntervalSeconds
            )
        }
        .onChange(of: autoRefreshIntervalSeconds) { _, newInterval in
            buildFeedStore.configureAutoRefresh(
                enabled: autoRefreshEnabled,
                intervalSeconds: newInterval
            )
        }
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
