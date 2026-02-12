import SwiftUI

struct ContentView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore
    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshIntervalSeconds") private var autoRefreshIntervalSeconds: Double = 60

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
