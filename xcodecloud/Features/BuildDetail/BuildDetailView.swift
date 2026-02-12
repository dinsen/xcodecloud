import SwiftUI

struct BuildDetailView: View {
    let run: BuildRunSummary

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
        }
        .navigationTitle(run.displayNumber)
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
}
