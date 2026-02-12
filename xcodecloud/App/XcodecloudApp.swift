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
        Settings {
            NavigationStack {
                SettingsView()
                    .environment(buildFeedStore)
            }
        }
#endif
    }
}
