import Foundation

struct AppStoreConnectCredentials: Codable, Sendable, Equatable {
    var keyID: String
    var issuerID: String
    var privateKeyPEM: String

    nonisolated init(
        keyID: String = "",
        issuerID: String = "",
        privateKeyPEM: String = ""
    ) {
        self.keyID = keyID
        self.issuerID = issuerID
        self.privateKeyPEM = privateKeyPEM
    }

    nonisolated var isComplete: Bool {
        !keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated var isEmpty: Bool {
        keyID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        issuerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    nonisolated func trimmed() -> AppStoreConnectCredentials {
        AppStoreConnectCredentials(
            keyID: keyID.trimmingCharacters(in: .whitespacesAndNewlines),
            issuerID: issuerID.trimmingCharacters(in: .whitespacesAndNewlines),
            privateKeyPEM: privateKeyPEM.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
