import Foundation

struct BuildRunDiagnostics: Sendable, Equatable {
    let actions: [BuildActionDiagnostics]

    nonisolated var totalIssues: Int {
        actions.reduce(0) { $0 + $1.issues.count }
    }

    nonisolated var totalTestResults: Int {
        actions.reduce(0) { $0 + $1.testResults.count }
    }
}

struct BuildActionDiagnostics: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let actionType: String?
    let executionProgress: String?
    let completionStatus: String?
    let startedDate: Date?
    let finishedDate: Date?
    let issueCounts: BuildIssueCounts
    let issues: [BuildIssueDiagnostics]
    let testResults: [BuildTestResultDiagnostics]
    let artifacts: [BuildArtifactDiagnostics]
}

struct BuildIssueDiagnostics: Identifiable, Sendable, Equatable {
    let id: String
    let issueType: String?
    let category: String?
    let message: String?
    let fileSource: String?
}

struct BuildTestResultDiagnostics: Identifiable, Sendable, Equatable {
    let id: String
    let className: String?
    let name: String?
    let status: String?
    let message: String?
    let fileSource: String?
}

struct BuildArtifactDiagnostics: Identifiable, Sendable, Equatable {
    let id: String
    let fileType: String?
    let fileName: String?
    let fileSize: Int?
    let downloadURL: URL?
}
