import Foundation

struct CIWorkflowSummary: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let isEnabled: Bool
    let isLockedForEditing: Bool
    let cleanByDefault: Bool
    let repositoryName: String?
    let xcodeVersion: String?
    let macOSVersion: String?
    let lastModifiedDate: Date?
}
