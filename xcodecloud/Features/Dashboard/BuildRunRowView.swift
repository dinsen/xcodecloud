import SwiftUI

struct BuildRunRowView: View {
    let run: BuildRunSummary
    let showsAppName: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: run.status.symbolName)
                .foregroundStyle(run.status.accentColor)
                .font(.title3)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(run.workflowName)
                        .font(.headline)
                    Spacer()
                    Text(run.displayNumber)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                if showsAppName, let app = run.app {
                    Text(app.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 12) {
                    Text(run.status.title)
                        .font(.caption)
                        .foregroundStyle(run.status.accentColor)

                    if let sourceBranch = run.sourceBranch {
                        Label(sourceBranch, systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if run.issueCounts.total > 0 {
                        Label("\(run.issueCounts.total)", systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                if run.status == .running, let startedDate = run.startedDate ?? run.createdDate {
                    HStack(spacing: 4) {
                        Text("Elapsed")
                        Text(startedDate, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                } else if let date = run.timestamp {
                    Text(date.shortDateTimeString())
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }

    init(run: BuildRunSummary, showsAppName: Bool = true) {
        self.run = run
        self.showsAppName = showsAppName
    }
}

extension BuildStatus {
    var accentColor: Color {
        switch self {
        case .running: return .blue
        case .succeeded: return .green
        case .failed: return .red
        case .canceled: return .orange
        case .skipped: return .yellow
        case .unknown: return .secondary
        }
    }
}
