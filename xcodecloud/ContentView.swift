import SwiftUI

struct ContentView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshIntervalSeconds") private var autoRefreshIntervalSeconds: Double = 60
    @AppStorage("liveStatusEnabled") private var liveStatusEnabled = false
    @AppStorage("liveStatusEndpointURL") private var liveStatusEndpointURL = ""
    @AppStorage("liveStatusPollIntervalSeconds") private var liveStatusPollIntervalSeconds: Double = 30

    private static let allAppsFilterValue = "__all_apps__"

    private var appFilterIconName: String {
        buildFeedStore.dashboardFilterAppID == nil
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill"
    }

    private var appFilterBinding: Binding<String> {
        Binding(
            get: { buildFeedStore.dashboardFilterAppID ?? Self.allAppsFilterValue },
            set: { newValue in
                let appID = newValue == Self.allAppsFilterValue ? nil : newValue
                buildFeedStore.setDashboardFilter(appID: appID)
            }
        )
    }

#if os(macOS)
    @Environment(\.openSettings) private var openSettingsAction
#endif

    @State private var isShowingSettings = false
    @State private var isShowingBuildTrigger = false

    var body: some View {
        NavigationStack {
            BuildDashboardView()
            .navigationTitle(buildFeedStore.isMonitoringAllApps ? "Portfolio" : "Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Picker(selection: appFilterBinding) {
                        Text("All Apps").tag(Self.allAppsFilterValue)
                        ForEach(buildFeedStore.dashboardFilterOptions) { app in
                            Text(app.displayName).tag(app.id)
                        }
                    } label: {
                        Image(systemName: appFilterIconName)
                            .accessibilityLabel(buildFeedStore.dashboardFilterApp?.name ?? "All Apps")
                    }
                    .pickerStyle(.menu)
                    .accessibilityIdentifier("dashboard-app-filter")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task {
                            await buildFeedStore.refreshBuildRuns()
                        }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .disabled(buildFeedStore.isLoadingBuildRuns)
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingBuildTrigger = true
                    } label: {
                        Label("Run Build", systemImage: "play.circle")
                    }
                    .disabled(
                        !buildFeedStore.hasCompleteCredentials ||
                        buildFeedStore.selectedApp == nil
                    )
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("open-settings-button")
                }
            }
        }
        .task {
            await buildFeedStore.loadInitialState()
            buildFeedStore.configureAutoRefresh(
                enabled: autoRefreshEnabled,
                intervalSeconds: autoRefreshIntervalSeconds
            )
            buildFeedStore.configureLiveStatusPolling(
                enabled: liveStatusEnabled,
                endpoint: liveStatusEndpointURL,
                intervalSeconds: liveStatusPollIntervalSeconds
            )
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
        .onChange(of: liveStatusEnabled) { _, isEnabled in
            buildFeedStore.configureLiveStatusPolling(
                enabled: isEnabled,
                endpoint: liveStatusEndpointURL,
                intervalSeconds: liveStatusPollIntervalSeconds
            )
        }
        .onChange(of: liveStatusEndpointURL) { _, newEndpoint in
            buildFeedStore.configureLiveStatusPolling(
                enabled: liveStatusEnabled,
                endpoint: newEndpoint,
                intervalSeconds: liveStatusPollIntervalSeconds
            )
        }
        .onChange(of: liveStatusPollIntervalSeconds) { _, newInterval in
            buildFeedStore.configureLiveStatusPolling(
                enabled: liveStatusEnabled,
                endpoint: liveStatusEndpointURL,
                intervalSeconds: newInterval
            )
        }
#if !os(macOS)
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(buildFeedStore)
            }
        }
#endif
        .sheet(isPresented: $isShowingBuildTrigger) {
            BuildTriggerSheetView()
                .environment(buildFeedStore)
        }
    }

    private func openSettings() {
#if os(macOS)
        openSettingsAction()
#else
        isShowingSettings = true
#endif
    }
}

#Preview {
    ContentView()
        .environment(BuildFeedStore())
}
