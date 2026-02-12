import SwiftUI

struct BuildDashboardView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    var body: some View {
        Group {
            if !buildFeedStore.hasCompleteCredentials {
                ContentUnavailableView(
                    "Credentials Missing",
                    systemImage: "key.slash",
                    description: Text("Open Settings to add App Store Connect API credentials.")
                )
            } else if buildFeedStore.selectedApp == nil {
                ContentUnavailableView(
                    "Select an App",
                    systemImage: "app.badge",
                    description: Text("Open Settings and choose which App Store Connect app to monitor.")
                )
            } else if buildFeedStore.isLoadingBuildRuns, buildFeedStore.buildRuns.isEmpty {
                ProgressView("Loading Builds...")
            } else if let errorMessage = buildFeedStore.errorMessage, buildFeedStore.buildRuns.isEmpty {
                ContentUnavailableView(
                    "Unable to Load Builds",
                    systemImage: "exclamationmark.triangle",
                    description: Text(errorMessage)
                )
            } else if buildFeedStore.buildRuns.isEmpty {
                ContentUnavailableView(
                    "No Build Runs",
                    systemImage: "tray",
                    description: Text(
                        buildFeedStore.isMonitoringAllApps
                        ? "No recent Xcode Cloud build runs were returned across monitored apps."
                        : "No recent Xcode Cloud build runs were returned."
                    )
                )
            } else {
                List {
                    if buildFeedStore.isMonitoringAllApps {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Portfolio")
                                    .font(.headline)
                                Text("Monitoring all apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let lastUpdated = buildFeedStore.lastUpdated {
                                    Text("Updated \(lastUpdated.shortDateTimeString())")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    }
                            }
                        }
                    } else if let selectedApp = buildFeedStore.selectedApp {
                        Section {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedApp.name)
                                    .font(.headline)
                                Text(selectedApp.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)

                                if let lastUpdated = buildFeedStore.lastUpdated {
                                    Text("Updated \(lastUpdated.shortDateTimeString())")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if buildFeedStore.isMonitoringAllApps {
                        ForEach(buildFeedStore.appSections) { appSection in
                            Section(appSection.app.name) {
                                ForEach(appSection.runs.prefix(6)) { run in
                                    NavigationLink {
                                        BuildDetailView(run: run)
                                    } label: {
                                        BuildRunRowView(run: run, showsAppName: false)
                                    }
                                }
                            }
                        }
                    } else {
                        ForEach(buildFeedStore.workflowSections) { section in
                            Section(section.workflowName) {
                                ForEach(section.runs) { run in
                                    NavigationLink {
                                        BuildDetailView(run: run)
                                    } label: {
                                        BuildRunRowView(run: run)
                                    }
                                }
                            }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #else
                .listStyle(.insetGrouped)
                #endif
                .refreshable {
                    await buildFeedStore.refreshBuildRuns()
                }
            }
        }
        .accessibilityIdentifier("dashboard-status-view")
    }
}
