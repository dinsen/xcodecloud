import SwiftUI

@main
struct XcodecloudApp: App {
    @State private var buildFeedStore = BuildFeedStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(buildFeedStore)
        }
#if os(macOS)
        MenuBarExtra {
            MenuBarRootView()
                .environment(buildFeedStore)
        } label: {
            Label("Xcode Cloud", systemImage: buildFeedStore.menuBarSymbolName)
        }
        .menuBarExtraStyle(.window)

        Settings {
            NavigationStack {
                SettingsView()
                    .environment(buildFeedStore)
            }
        }
#endif
    }
}
