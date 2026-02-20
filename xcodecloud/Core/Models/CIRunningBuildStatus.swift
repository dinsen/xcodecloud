import Foundation

struct CIRunningBuildStatus: Sendable, Equatable {
    let buildsRunning: Bool
    let runningCount: Int
    let singleBuildStartedAt: Date?
    let checkedAt: Date?

    nonisolated init(buildsRunning: Bool, runningCount: Int, singleBuildStartedAt: Date?, checkedAt: Date?) {
        self.buildsRunning = buildsRunning
        self.runningCount = runningCount
        self.singleBuildStartedAt = singleBuildStartedAt
        self.checkedAt = checkedAt
    }
}
