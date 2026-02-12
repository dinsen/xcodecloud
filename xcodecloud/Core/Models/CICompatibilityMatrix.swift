import Foundation

struct CICompatibilityMatrix: Sendable, Equatable {
    let xcodeVersions: [CIXcodeCompatibility]
}

struct CIXcodeCompatibility: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let version: String?
    let compatibleMacOSVersions: [String]
}
