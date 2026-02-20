import Foundation

protocol BuildLiveActivityManaging {
    @MainActor
    func update(appID: String, appName: String, runningCount: Int, singleBuildStartedAt: Date?) async

    @MainActor
    func end() async
}

#if os(iOS)
import ActivityKit

struct BuildLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var appName: String
        var runningCount: Int
        var singleBuildStartedAt: Date?
        var updatedAt: Date
    }

    let appID: String
}

@MainActor
final class BuildLiveActivityManager: BuildLiveActivityManaging {
    private var activity: Activity<BuildLiveActivityAttributes>?

    func update(appID: String, appName: String, runningCount: Int, singleBuildStartedAt: Date?) async {
        guard #available(iOS 16.2, *) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        if runningCount <= 0 {
            await end()
            return
        }

        let state = BuildLiveActivityAttributes.ContentState(
            appName: appName,
            runningCount: runningCount,
            singleBuildStartedAt: singleBuildStartedAt,
            updatedAt: Date()
        )

        if let activity, activity.attributes.appID == appID {
            await activity.update(ActivityContent(state: state, staleDate: Date().addingTimeInterval(300)))
            return
        }

        if let activity {
            await activity.end(nil, dismissalPolicy: .immediate)
        }

        let attributes = BuildLiveActivityAttributes(appID: appID)
        do {
            activity = try Activity.request(
                attributes: attributes,
                content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(300)),
                pushType: nil
            )
        } catch {
            activity = nil
        }
    }

    func end() async {
        guard #available(iOS 16.2, *) else { return }
        guard let activity else { return }
        await activity.end(nil, dismissalPolicy: .immediate)
        self.activity = nil
    }
}
#else
@MainActor
final class BuildLiveActivityManager: BuildLiveActivityManaging {
    func update(appID: String, appName: String, runningCount: Int, singleBuildStartedAt: Date?) async {}
    func end() async {}
}
#endif
