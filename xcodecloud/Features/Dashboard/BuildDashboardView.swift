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
                    description: Text("Open Settings and choose an app first.")
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
                        Section("Running Builds") {
                            if buildFeedStore.portfolioRunningBuilds.isEmpty {
                                Text("No running builds.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(buildFeedStore.portfolioRunningBuilds) { run in
                                    NavigationLink {
                                        BuildDetailView(run: run)
                                    } label: {
                                        BuildRunRowView(run: run)
                                    }
                                }
                            }
                        }

                        Section("Failed Builds") {
                            if buildFeedStore.portfolioFailedBuilds.isEmpty {
                                Text("No failed builds.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(buildFeedStore.portfolioFailedBuilds) { run in
                                    NavigationLink {
                                        BuildDetailView(run: run)
                                    } label: {
                                        BuildRunRowView(run: run)
                                    }
                                }
                            }
                        }

                        Section("Latest Successful Builds (20)") {
                            if buildFeedStore.portfolioSuccessfulBuilds.isEmpty {
                                Text("No successful builds.")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(buildFeedStore.portfolioSuccessfulBuilds) { run in
                                    NavigationLink {
                                        BuildDetailView(run: run)
                                    } label: {
                                        BuildRunRowView(run: run)
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
