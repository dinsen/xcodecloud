import SwiftUI

struct RepositoryTopologyView: View {
    @Environment(BuildFeedStore.self) private var buildFeedStore

    private var primaryRepositories: [CIRepositorySummary] {
        buildFeedStore.repositories.filter(\.isPrimary)
    }

    private var additionalRepositories: [CIRepositorySummary] {
        buildFeedStore.repositories.filter { !$0.isPrimary }
    }

    var body: some View {
        List {
            if buildFeedStore.isLoadingRepositories {
                Section {
                    ProgressView("Loading repositories...")
                }
            } else if buildFeedStore.repositories.isEmpty {
                Section {
                    Text(buildFeedStore.repositoryMessage ?? "No repositories found.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Primary Repositories") {
                    if primaryRepositories.isEmpty {
                        Text("No primary repositories returned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(primaryRepositories) { repository in
                            repositoryRow(repository)
                        }
                    }
                }

                Section("Additional Repositories") {
                    if additionalRepositories.isEmpty {
                        Text("No additional repositories returned.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(additionalRepositories) { repository in
                            repositoryRow(repository)
                        }
                    }
                }
            }
        }
        .navigationTitle("Repositories")
        .task {
            await buildFeedStore.loadRepositories()
        }
        .refreshable {
            await buildFeedStore.loadRepositories()
        }
    }

    @ViewBuilder
    private func repositoryRow(_ repository: CIRepositorySummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(repository.displayName)
                    .font(.headline)
                Spacer()
                healthLabel(for: repository.health)
            }

            if let provider = repository.provider {
                Text(provider)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let defaultBranch = repository.defaultBranch {
                Text("Default branch: \(defaultBranch)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let lastAccessedDate = repository.lastAccessedDate {
                Text("Last accessed: \(lastAccessedDate.shortDateTimeString())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func healthLabel(for health: CIRepositorySummary.Health) -> some View {
        switch health {
        case .healthy:
            Text("Healthy")
                .font(.caption)
                .foregroundStyle(.green)
        case .warning(let reason):
            Text(reason)
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

#Preview {
    NavigationStack {
        RepositoryTopologyView()
            .environment(BuildFeedStore())
    }
}
