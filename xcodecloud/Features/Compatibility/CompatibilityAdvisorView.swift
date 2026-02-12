import SwiftUI

struct CompatibilityAdvisorView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    var body: some View {
        List {
            if buildFeedStore.isLoadingCompatibility {
                Section {
                    ProgressView("Loading compatibility matrix...")
                }
            } else if let matrix = buildFeedStore.compatibilityMatrix {
                if !buildFeedStore.workflows.isEmpty {
                    Section("Current Workflows") {
                        ForEach(buildFeedStore.workflows) { workflow in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(workflow.name)
                                        .font(.headline)
                                    Spacer()
                                    statusLabel(for: compatibilityState(for: workflow, matrix: matrix))
                                }

                                if let xcodeVersion = workflow.xcodeVersion {
                                    Text("Xcode: \(xcodeVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let macOSVersion = workflow.macOSVersion {
                                    Text("macOS: \(macOSVersion)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }

                Section("Supported Xcode / macOS") {
                    ForEach(matrix.xcodeVersions) { xcode in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(xcode.name)
                                .font(.headline)

                            if xcode.compatibleMacOSVersions.isEmpty {
                                Text("No compatible macOS versions reported.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(xcode.compatibleMacOSVersions.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            } else if let compatibilityMessage = buildFeedStore.compatibilityMessage {
                Section {
                    Text(compatibilityMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Compatibility")
        .task {
            await buildFeedStore.loadCompatibilityMatrix()
            if buildFeedStore.workflows.isEmpty {
                await buildFeedStore.loadWorkflows()
            }
        }
        .refreshable {
            await buildFeedStore.loadCompatibilityMatrix()
        }
    }

    private func compatibilityState(for workflow: CIWorkflowSummary, matrix: CICompatibilityMatrix) -> CompatibilityState {
        guard let workflowXcodeVersion = workflow.xcodeVersion,
              let workflowMacOSVersion = workflow.macOSVersion else {
            return .unknown
        }

        guard let xcodeVersion = matrix.xcodeVersions.first(where: {
            $0.name.localizedCaseInsensitiveCompare(workflowXcodeVersion) == .orderedSame
        }) else {
            return .needsReview
        }

        let isCompatible = xcodeVersion.compatibleMacOSVersions.contains {
            $0.localizedCaseInsensitiveCompare(workflowMacOSVersion) == .orderedSame
        }

        return isCompatible ? .compatible : .needsReview
    }

    @ViewBuilder
    private func statusLabel(for state: CompatibilityState) -> some View {
        switch state {
        case .compatible:
            Text("Compatible")
                .font(.caption)
                .foregroundStyle(.green)
        case .needsReview:
            Text("Needs Review")
                .font(.caption)
                .foregroundStyle(.orange)
        case .unknown:
            Text("Unknown")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum CompatibilityState {
    case compatible
    case needsReview
    case unknown
}

#Preview {
    NavigationStack {
        CompatibilityAdvisorView()
            .environment(BuildFeedStore())
    }
}
