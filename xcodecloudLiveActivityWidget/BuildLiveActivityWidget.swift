import ActivityKit
import WidgetKit
import SwiftUI

struct BuildLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var appName: String
        var runningCount: Int
        var singleBuildStartedAt: Date?
        var updatedAt: Date
    }

    let appID: String
}

struct BuildLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BuildLiveActivityAttributes.self) { context in
            VStack(alignment: .leading, spacing: 8) {
                Text(context.state.appName)
                    .font(.headline)
                Text("\(context.state.runningCount) build\(context.state.runningCount == 1 ? "" : "s") running")
                    .font(.subheadline)
                if context.state.runningCount == 1, let startedAt = context.state.singleBuildStartedAt {
                    HStack(spacing: 4) {
                        Text("Elapsed")
                        Text(startedAt, style: .timer)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
                Text("Updated \(context.state.updatedAt, style: .time)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
            .activityBackgroundTint(.black.opacity(0.12))
            .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Builds", systemImage: "hammer.fill")
                        .font(.caption)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.runningCount == 1, let startedAt = context.state.singleBuildStartedAt {
                        Text(startedAt, style: .timer)
                            .font(.headline.monospacedDigit())
                    } else {
                        Text("\(context.state.runningCount)")
                            .font(.title3)
                            .bold()
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(context.state.appName)
                            .lineLimit(1)

                        Spacer()

                        if context.state.runningCount == 1, let startedAt = context.state.singleBuildStartedAt {
                            Text(startedAt, style: .timer)
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .font(.caption)
                }
            } compactLeading: {
                Image(systemName: "hammer.fill")
            } compactTrailing: {
                if context.state.runningCount == 1, let startedAt = context.state.singleBuildStartedAt {
                    Text(startedAt, style: .timer)
                        .font(.caption2.monospacedDigit())
                } else {
                    Text("\(context.state.runningCount)")
                        .monospacedDigit()
                }
            } minimal: {
                Text("\(context.state.runningCount)")
                    .monospacedDigit()
            }
        }
    }
}
