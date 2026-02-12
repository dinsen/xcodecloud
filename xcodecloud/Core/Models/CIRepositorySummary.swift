import Foundation

struct CIRepositorySummary: Identifiable, Sendable, Equatable {
    enum Health: Sendable, Equatable {
        case healthy
        case warning(String)
    }

    let id: String
    let displayName: String
    let ownerName: String?
    let repositoryName: String?
    let provider: String?
    let defaultBranch: String?
    let lastAccessedDate: Date?
    let isPrimary: Bool

    nonisolated var health: Health {
        if defaultBranch?.isEmpty ?? true {
            return .warning("No default branch")
        }

        if let lastAccessedDate {
            let staleThreshold = Date().addingTimeInterval(-60 * 60 * 24 * 30)
            if lastAccessedDate < staleThreshold {
                return .warning("No recent access in 30+ days")
            }
        }

        return .healthy
    }
}
