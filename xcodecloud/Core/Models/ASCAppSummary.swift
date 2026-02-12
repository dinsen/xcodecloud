import Foundation

struct ASCAppSummary: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let bundleID: String

    nonisolated init(id: String, name: String, bundleID: String) {
        self.id = id
        self.name = name
        self.bundleID = bundleID
    }

    nonisolated var displayName: String {
        "\(name) (\(bundleID))"
    }
}
