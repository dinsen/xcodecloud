import ActivityKit
import WidgetKit
import SwiftUI

struct BuildLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var appName: String
        var runningCount: Int
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
                    Text("\(context.state.runningCount)")
                        .font(.title3)
                        .bold()
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.state.appName)
                        .font(.caption)
                        .lineLimit(1)
                }
            } compactLeading: {
                Image(systemName: "hammer.fill")
            } compactTrailing: {
                Text("\(context.state.runningCount)")
                    .monospacedDigit()
            } minimal: {
                Text("\(context.state.runningCount)")
                    .monospacedDigit()
            }
        }
    }
}
