import SwiftUI

struct ContentView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

#if os(macOS)
    @Environment(\.openSettings) private var openSettingsAction
#endif

    @State private var isShowingSettings = false

    var body: some View {
        NavigationStack {
            Group {
                if buildFeedStore.hasCompleteCredentials {
                    ContentUnavailableView(
                        "Dashboard Coming Soon",
                        systemImage: "chart.bar.horizontal.page",
                        description: Text("Credentials are configured. Next step is loading build runs from Xcode Cloud.")
                    )
                } else {
                    ContentUnavailableView(
                        "Credentials Missing",
                        systemImage: "key.slash",
                        description: Text("Open Settings to add App Store Connect API credentials.")
                    )
                }
            }
            .accessibilityIdentifier("dashboard-status-view")
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        openSettings()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .accessibilityIdentifier("open-settings-button")
                }
            }
            .onAppear {
                buildFeedStore.reloadCredentials()
            }
        }
#if !os(macOS)
        .sheet(isPresented: $isShowingSettings) {
            NavigationStack {
                SettingsView()
                    .environment(buildFeedStore)
            }
        }
#endif
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
