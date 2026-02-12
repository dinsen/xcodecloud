import Foundation

struct CIRunningBuildStatus: Sendable, Equatable {
    let buildsRunning: Bool
    let runningCount: Int
    let checkedAt: Date?

    nonisolated init(buildsRunning: Bool, runningCount: Int, checkedAt: Date?) {
        self.buildsRunning = buildsRunning
        self.runningCount = runningCount
        self.checkedAt = checkedAt
    }
}
