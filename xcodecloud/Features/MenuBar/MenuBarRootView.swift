#if os(macOS)
import SwiftUI

struct MenuBarRootView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore
    @Environment(\.openSettings) private var openSettings

    @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = true
    @AppStorage("autoRefreshIntervalSeconds") private var autoRefreshIntervalSeconds: Double = 60

    @State private var selectedRunID: String?

    private var selectedRun: BuildRunSummary? {
        if let selectedRunID {
            return buildFeedStore.buildRuns.first(where: { $0.id == selectedRunID })
        }
        return buildFeedStore.buildRuns.first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(buildFeedStore.isMonitoringAllApps ? "All Apps" : (buildFeedStore.dashboardFilterApp?.name ?? "Filtered App"))
                        .font(.headline)
                    if let filteredApp = buildFeedStore.dashboardFilterApp, !buildFeedStore.isMonitoringAllApps {
                        Text(filteredApp.bundleID)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else if buildFeedStore.isMonitoringAllApps {
                        Text("Portfolio monitoring")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    Task {
                        await buildFeedStore.refreshBuildRuns()
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(buildFeedStore.isLoadingBuildRuns)

                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
            }

            if let lastUpdated = buildFeedStore.lastUpdated {
                Text("Updated \(lastUpdated.shortDateTimeString())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !buildFeedStore.hasCompleteCredentials {
                Text("Add credentials in Settings to load builds.")
                    .foregroundStyle(.secondary)
            } else if buildFeedStore.isLoadingBuildRuns && buildFeedStore.buildRuns.isEmpty {
                ProgressView("Loading builds...")
            } else if let errorMessage = buildFeedStore.errorMessage, buildFeedStore.buildRuns.isEmpty {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(buildFeedStore.buildRuns.prefix(10)) { run in
                            Button {
                                selectedRunID = run.id
                            } label: {
                                BuildRunRowView(run: run)
                                    .padding(6)
                                    .background(selectedRunID == run.id ? Color.gray.opacity(0.15) : .clear)
                                    .clipShape(.rect(cornerRadius: 8))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 220)

                if let selectedRun {
                    Divider()
                    BuildDetailPanel(run: selectedRun)
                }
            }
        }
        .padding(12)
        .frame(width: 420)
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
    }
}

private struct BuildDetailPanel: View {
    let run: BuildRunSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(run.displayNumber)
                    .font(.headline)
                Spacer()
                Label(run.status.title, systemImage: run.status.symbolName)
                    .foregroundStyle(run.status.accentColor)
            }

            if let sourceBranch = run.sourceBranch {
                Text(sourceBranch)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 12) {
                if let sourceCommitWebURL = run.sourceCommitWebURL {
                    Link(destination: sourceCommitWebURL) {
                        Label("Commit", systemImage: "link")
                    }
                }

                if let buildWebURL = run.buildWebURL {
                    Link(destination: buildWebURL) {
                        Label("Build", systemImage: "safari")
                    }
                }
            }
            .font(.caption)
        }
    }
}
#endif
