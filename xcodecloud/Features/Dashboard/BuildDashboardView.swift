import SwiftUI

struct BuildDashboardView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    private static let allAppsFilterValue = "__all_apps__"

    private var appFilterBinding: Binding<String> {
        Binding(
            get: { buildFeedStore.dashboardFilterAppID ?? Self.allAppsFilterValue },
            set: { newValue in
                let appID = newValue == Self.allAppsFilterValue ? nil : newValue
                buildFeedStore.setDashboardFilter(appID: appID)
            }
        )
    }

    var body: some View {
        Group {
            if !buildFeedStore.hasCompleteCredentials {
                ContentUnavailableView(
                    "Credentials Missing",
                    systemImage: "key.slash",
                    description: Text("Open Settings to add App Store Connect API credentials.")
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
                    Section {
                        Picker("App", selection: appFilterBinding) {
                            Text("All Apps")
                                .tag(Self.allAppsFilterValue)

                            ForEach(buildFeedStore.dashboardFilterOptions) { app in
                                Text(app.displayName)
                                    .tag(app.id)
                            }
                        }
                        .pickerStyle(.menu)
                        .accessibilityIdentifier("dashboard-app-filter")
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 4) {
                            if let filteredApp = buildFeedStore.dashboardFilterApp {
                                Text(filteredApp.name)
                                    .font(.headline)
                                Text(filteredApp.bundleID)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("Portfolio")
                                    .font(.headline)
                                Text("Monitoring all apps")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            if let lastUpdated = buildFeedStore.lastUpdated {
                                Text("Updated \(lastUpdated.shortDateTimeString())")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

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
