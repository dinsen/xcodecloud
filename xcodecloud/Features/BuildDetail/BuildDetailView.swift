import SwiftUI

struct BuildDetailView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    let run: BuildRunSummary
    @State private var diagnostics: BuildRunDiagnostics?
    @State private var diagnosticsMessage: String?
    @State private var isLoadingDiagnostics = false

    var body: some View {
        List {
            Section("Build") {
                if let app = run.app {
                    detailRow("App", value: app.name)
                    detailRow("Bundle ID", value: app.bundleID)
                }
                detailRow("Workflow", value: run.workflowName)
                detailRow("Run", value: run.displayNumber)
                detailRow("Status", value: run.status.title)
                detailRow("Execution", value: run.executionProgress ?? "-")
                detailRow("Completion", value: run.completionStatus ?? "-")
            }

            Section("Timing") {
                detailRow("Created", value: run.createdDate?.shortDateTimeString() ?? "-")
                detailRow("Started", value: run.startedDate?.shortDateTimeString() ?? "-")
                detailRow("Finished", value: run.finishedDate?.shortDateTimeString() ?? "-")
            }

            Section("Source") {
                detailRow("Branch/Tag", value: run.sourceBranch ?? "-")
                detailRow("Commit", value: run.sourceCommitSHA ?? "-")

                if let sourceCommitMessage = run.sourceCommitMessage, !sourceCommitMessage.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Message")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(sourceCommitMessage)
                            .font(.body)
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("Issues") {
                detailRow("Errors", value: "\(run.issueCounts.errors)")
                detailRow("Warnings", value: "\(run.issueCounts.warnings)")
                detailRow("Test Failures", value: "\(run.issueCounts.testFailures)")
                detailRow("Analyzer Warnings", value: "\(run.issueCounts.analyzerWarnings)")
            }

            Section("Links") {
                if let sourceCommitWebURL = run.sourceCommitWebURL {
                    Link(destination: sourceCommitWebURL) {
                        Label("Open Source Commit", systemImage: "link")
                    }
                }

                if let buildWebURL = run.buildWebURL {
                    Link(destination: buildWebURL) {
                        Label("Open Build Run", systemImage: "safari")
                    }
                }

                if run.sourceCommitWebURL == nil && run.buildWebURL == nil {
                    Text("No links available for this run.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Diagnostics") {
                if isLoadingDiagnostics {
                    ProgressView("Loading diagnostics...")
                } else if let diagnostics {
                    if diagnostics.actions.isEmpty {
                        Text("No action diagnostics were returned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(diagnostics.actions) { action in
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(action.name)
                                        .font(.headline)
                                    Spacer()
                                    Text(action.completionStatus ?? action.executionProgress ?? "Unknown")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                HStack(spacing: 12) {
                                    Label("\(action.issues.count)", systemImage: "exclamationmark.triangle")
                                    Label("\(action.testResults.count)", systemImage: "checklist.checked")
                                    Label("\(action.artifacts.count)", systemImage: "doc")
                                }
                                .font(.caption)
                                .foregroundStyle(.secondary)

                                if !action.issues.isEmpty {
                                    Text("Issues")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(action.issues.prefix(2)) { issue in
                                        Text(issue.message ?? issue.issueType ?? "Issue")
                                            .font(.caption)
                                    }
                                }

                                if !action.testResults.isEmpty {
                                    Text("Tests")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(action.testResults.prefix(2)) { testResult in
                                        Text(testResult.name ?? testResult.className ?? "Test Result")
                                            .font(.caption)
                                    }
                                }

                                if !action.artifacts.isEmpty {
                                    Text("Artifacts")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    ForEach(action.artifacts.prefix(2)) { artifact in
                                        if let downloadURL = artifact.downloadURL {
                                            Link(destination: downloadURL) {
                                                Text(artifact.fileName ?? artifact.fileType ?? "Artifact")
                                                    .font(.caption)
                                            }
                                        } else {
                                            Text(artifact.fileName ?? artifact.fileType ?? "Artifact")
                                                .font(.caption)
                                        }
                                    }
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                } else if let diagnosticsMessage {
                    Text(diagnosticsMessage)
                        .foregroundStyle(.secondary)
                } else {
                    Text("No diagnostics loaded yet.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(run.displayNumber)
        .task(id: run.id) {
            await loadDiagnostics()
        }
    }

    @ViewBuilder
    private func detailRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }

    private func loadDiagnostics() async {
        isLoadingDiagnostics = true
        diagnosticsMessage = nil
        defer { isLoadingDiagnostics = false }

        do {
            let diagnostics = try await buildFeedStore.loadBuildDiagnostics(runID: run.id)
            self.diagnostics = diagnostics
            self.diagnosticsMessage = nil
        } catch {
            self.diagnostics = nil
            self.diagnosticsMessage = buildFeedStore.sanitizedMessage(for: error)
        }
    }
}
