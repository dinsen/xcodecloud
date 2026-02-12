import SwiftUI

struct BuildTriggerSheetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(BuildFeedStore.self) private var buildFeedStore

    @State private var selectedWorkflowID: String?
    @State private var cleanBuild = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Workflow") {
                    if buildFeedStore.isLoadingWorkflows {
                        ProgressView("Loading workflows...")
                    } else if buildFeedStore.workflows.isEmpty {
                        Text(buildFeedStore.buildTriggerMessage ?? "No workflows available.")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Workflow", selection: workflowSelectionBinding) {
                            ForEach(buildFeedStore.workflows) { workflow in
                                HStack {
                                    Text(workflow.name)
                                    if !workflow.isEnabled {
                                        Text("(Disabled)")
                                    }
                                }
                                .tag(Optional(workflow.id))
                            }
                        }

                        if let selectedWorkflow = selectedWorkflow {
                            if let repository = selectedWorkflow.repositoryName {
                                detailRow("Repository", value: repository)
                            }
                            if let xcodeVersion = selectedWorkflow.xcodeVersion {
                                detailRow("Xcode", value: xcodeVersion)
                            }
                            if let macOSVersion = selectedWorkflow.macOSVersion {
                                detailRow("macOS", value: macOSVersion)
                            }
                        }
                    }
                }

                Section("Options") {
                    Toggle("Clean Build", isOn: $cleanBuild)
                }

                if let buildTriggerMessage = buildFeedStore.buildTriggerMessage {
                    Section {
                        Text(buildTriggerMessage)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Run Build")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        Task {
                            guard let selectedWorkflowID else { return }
                            let started = await buildFeedStore.triggerBuild(
                                workflowID: selectedWorkflowID,
                                clean: cleanBuild
                            )
                            if started {
                                dismiss()
                            }
                        }
                    }
                    .disabled(selectedWorkflowID == nil || buildFeedStore.isTriggeringBuild)
                }
            }
            .task {
                await buildFeedStore.loadWorkflows()
                if selectedWorkflowID == nil {
                    selectedWorkflowID = buildFeedStore.workflows.first?.id
                    if let first = buildFeedStore.workflows.first {
                        cleanBuild = first.cleanByDefault
                    }
                }
            }
        }
    }

    private var selectedWorkflow: CIWorkflowSummary? {
        guard let selectedWorkflowID else { return nil }
        return buildFeedStore.workflows.first(where: { $0.id == selectedWorkflowID })
    }

    private var workflowSelectionBinding: Binding<String?> {
        Binding {
            selectedWorkflowID
        } set: { newValue in
            selectedWorkflowID = newValue
            if let id = newValue,
               let workflow = buildFeedStore.workflows.first(where: { $0.id == id }) {
                cleanBuild = workflow.cleanByDefault
            }
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
}

#Preview {
    BuildTriggerSheetView()
        .environment(BuildFeedStore())
}
