import SwiftUI

struct WorkflowManagementView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    @State private var workflowPendingDelete: CIWorkflowSummary?
    @State private var workflowPendingDuplicate: CIWorkflowSummary?
    @State private var duplicateWorkflowName = ""

    var body: some View {
        List {
            if buildFeedStore.monitoringMode == .allApps {
                Section {
                    Text("Switch to Single App mode in Settings to manage workflows.")
                        .foregroundStyle(.secondary)
                }
            } else if buildFeedStore.isLoadingWorkflows {
                Section {
                    ProgressView("Loading workflows...")
                }
            } else if buildFeedStore.workflows.isEmpty {
                Section {
                    Text(buildFeedStore.workflowManagementMessage ?? "No workflows found.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(buildFeedStore.workflows) { workflow in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(workflow.name)
                                    .font(.headline)
                                if !workflow.isEnabled {
                                    Text("Disabled")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                                if workflow.isLockedForEditing {
                                    Text("Locked")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }

                            if let repositoryName = workflow.repositoryName {
                                Text(repositoryName)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            HStack(spacing: 10) {
                                Button(workflow.isEnabled ? "Disable" : "Enable") {
                                    Task {
                                        _ = await buildFeedStore.setWorkflowEnabled(
                                            workflowID: workflow.id,
                                            isEnabled: !workflow.isEnabled
                                        )
                                    }
                                }
                                .disabled(workflow.isLockedForEditing || buildFeedStore.isManagingWorkflows)

                                Button("Duplicate") {
                                    workflowPendingDuplicate = workflow
                                    duplicateWorkflowName = "\(workflow.name) Copy"
                                }
                                .disabled(buildFeedStore.isManagingWorkflows)

                                Button("Delete", role: .destructive) {
                                    workflowPendingDelete = workflow
                                }
                                .disabled(workflow.isLockedForEditing || buildFeedStore.isManagingWorkflows)
                            }
                            .font(.caption)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }

            if let workflowManagementMessage = buildFeedStore.workflowManagementMessage {
                Section {
                    Text(workflowManagementMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Workflows")
        .task {
            await buildFeedStore.loadWorkflows()
        }
        .refreshable {
            await buildFeedStore.loadWorkflows()
        }
        .alert(
            "Delete Workflow",
            isPresented: isDeleteAlertPresented,
            presenting: workflowPendingDelete
        ) { workflow in
            Button("Delete", role: .destructive) {
                Task {
                    _ = await buildFeedStore.deleteWorkflow(workflowID: workflow.id)
                }
                workflowPendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                workflowPendingDelete = nil
            }
        } message: { workflow in
            Text("Delete \(workflow.name)? This action cannot be undone.")
        }
        .alert("Duplicate Workflow", isPresented: isDuplicateAlertPresented) {
            TextField("New workflow name", text: $duplicateWorkflowName)
            Button("Duplicate") {
                guard let workflowPendingDuplicate else { return }
                Task {
                    _ = await buildFeedStore.duplicateWorkflow(
                        workflowID: workflowPendingDuplicate.id,
                        newName: duplicateWorkflowName
                    )
                }
                self.workflowPendingDuplicate = nil
            }
            Button("Cancel", role: .cancel) {
                workflowPendingDuplicate = nil
            }
        } message: {
            Text("Create a copy of this workflow.")
        }
    }

    private var isDeleteAlertPresented: Binding<Bool> {
        Binding {
            workflowPendingDelete != nil
        } set: { isPresented in
            if !isPresented {
                workflowPendingDelete = nil
            }
        }
    }

    private var isDuplicateAlertPresented: Binding<Bool> {
        Binding {
            workflowPendingDuplicate != nil
        } set: { isPresented in
            if !isPresented {
                workflowPendingDuplicate = nil
            }
        }
    }
}

#Preview {
    NavigationStack {
        WorkflowManagementView()
            .environment(BuildFeedStore())
    }
}
