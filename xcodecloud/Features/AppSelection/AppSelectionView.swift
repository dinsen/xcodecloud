import SwiftUI

struct AppSelectionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BuildFeedStore.self) private var buildFeedStore

    @State private var searchText = ""

    private var filteredApps: [ASCAppSummary] {
        let apps = buildFeedStore.availableApps
        guard !searchText.isEmpty else { return apps }

        return apps.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.bundleID.localizedStandardContains(searchText)
        }
    }

    var body: some View {
        List(filteredApps) { app in
            Button {
                Task {
                    await buildFeedStore.selectApp(app)
                    dismiss()
                }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name)
                            .foregroundStyle(.primary)
                        Text(app.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if buildFeedStore.selectedApp?.id == app.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .overlay {
            if buildFeedStore.isLoadingApps {
                ProgressView("Loading Apps...")
            } else if filteredApps.isEmpty {
                ContentUnavailableView(
                    "No Apps",
                    systemImage: "app.badge",
                    description: Text(buildFeedStore.appSelectionMessage ?? "No apps were returned for these credentials.")
                )
            }
        }
        .searchable(text: $searchText, prompt: "Search name or bundle ID")
        .navigationTitle("Select App")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        await buildFeedStore.loadApps()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(buildFeedStore.isLoadingApps)
            }
        }
        .task {
            if buildFeedStore.availableApps.isEmpty {
                await buildFeedStore.loadApps()
            }
        }
    }
}

#Preview {
    NavigationStack {
        AppSelectionView()
            .environment(BuildFeedStore())
    }
}
