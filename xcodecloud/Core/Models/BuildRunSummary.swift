import Foundation

struct BuildIssueCounts: Sendable, Equatable {
    let errors: Int
    let warnings: Int
    let testFailures: Int
    let analyzerWarnings: Int

    nonisolated init(errors: Int = 0, warnings: Int = 0, testFailures: Int = 0, analyzerWarnings: Int = 0) {
        self.errors = errors
        self.warnings = warnings
        self.testFailures = testFailures
        self.analyzerWarnings = analyzerWarnings
    }

    nonisolated var total: Int {
        errors + warnings + testFailures + analyzerWarnings
    }
}

enum BuildStatus: String, Sendable, Equatable {
    case running
    case succeeded
    case failed
    case canceled
    case skipped
    case unknown

    nonisolated static func derive(executionProgress: String?, completionStatus: String?) -> BuildStatus {
        let progress = executionProgress?.uppercased()
        let completion = completionStatus?.uppercased()

        if progress == "RUNNING" || progress == "PENDING" {
            return .running
        }

        switch completion {
        case "SUCCEEDED":
            return .succeeded
        case "FAILED", "ERRORED":
            return .failed
        case "CANCELED":
            return .canceled
        case "SKIPPED":
            return .skipped
        default:
            return .unknown
        }
    }

    nonisolated var title: String {
        switch self {
        case .running: return "Running"
        case .succeeded: return "Succeeded"
        case .failed: return "Failed"
        case .canceled: return "Canceled"
        case .skipped: return "Skipped"
        case .unknown: return "Unknown"
        }
    }

    nonisolated var priority: Int {
        switch self {
        case .failed: return 0
        case .running: return 1
        case .canceled: return 2
        case .skipped: return 3
        case .succeeded: return 4
        case .unknown: return 5
        }
    }

    nonisolated var symbolName: String {
        switch self {
        case .running: return "arrow.triangle.2.circlepath.circle.fill"
        case .succeeded: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .canceled: return "minus.circle.fill"
        case .skipped: return "forward.end.circle.fill"
        case .unknown: return "circle.dashed"
        }
    }
}

struct BuildRunSummary: Identifiable, Sendable, Equatable {
    let id: String
    let number: Int?
    let workflowName: String
    let app: ASCAppSummary?
    let status: BuildStatus
    let executionProgress: String?
    let completionStatus: String?
    let createdDate: Date?
    let startedDate: Date?
    let finishedDate: Date?
    let sourceBranch: String?
    let sourceCommitSHA: String?
    let sourceCommitMessage: String?
    let sourceCommitWebURL: URL?
    let buildWebURL: URL?
    let issueCounts: BuildIssueCounts

    nonisolated init(
        id: String,
        number: Int?,
        workflowName: String,
        app: ASCAppSummary? = nil,
        status: BuildStatus,
        executionProgress: String?,
        completionStatus: String?,
        createdDate: Date?,
        startedDate: Date?,
        finishedDate: Date?,
        sourceBranch: String?,
        sourceCommitSHA: String?,
        sourceCommitMessage: String?,
        sourceCommitWebURL: URL?,
        buildWebURL: URL?,
        issueCounts: BuildIssueCounts
    ) {
        self.id = id
        self.number = number
        self.workflowName = workflowName
        self.app = app
        self.status = status
        self.executionProgress = executionProgress
        self.completionStatus = completionStatus
        self.createdDate = createdDate
        self.startedDate = startedDate
        self.finishedDate = finishedDate
        self.sourceBranch = sourceBranch
        self.sourceCommitSHA = sourceCommitSHA
        self.sourceCommitMessage = sourceCommitMessage
        self.sourceCommitWebURL = sourceCommitWebURL
        self.buildWebURL = buildWebURL
        self.issueCounts = issueCounts
    }

    nonisolated var displayNumber: String {
        if let number { return "#\(number)" }
        return "-"
    }

    nonisolated var timestamp: Date? {
        startedDate ?? createdDate
    }
}

struct WorkflowBuildSection: Identifiable, Sendable, Equatable {
    let workflowName: String
    let runs: [BuildRunSummary]

    nonisolated var id: String { workflowName }
}

extension BuildRunSummary {
    nonisolated func withApp(_ app: ASCAppSummary) -> BuildRunSummary {
        BuildRunSummary(
            id: id,
            number: number,
            workflowName: workflowName,
            app: app,
            status: status,
            executionProgress: executionProgress,
            completionStatus: completionStatus,
            createdDate: createdDate,
            startedDate: startedDate,
            finishedDate: finishedDate,
            sourceBranch: sourceBranch,
            sourceCommitSHA: sourceCommitSHA,
            sourceCommitMessage: sourceCommitMessage,
            sourceCommitWebURL: sourceCommitWebURL,
            buildWebURL: buildWebURL,
            issueCounts: issueCounts
        )
    }
}

struct AppBuildSection: Identifiable, Sendable, Equatable {
    let app: ASCAppSummary
    let runs: [BuildRunSummary]

    nonisolated var id: String { app.id }
}
