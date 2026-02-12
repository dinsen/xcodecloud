import Foundation
import Testing
@testable import xcodecloud

struct AppStoreConnectCredentialsTests {
    @Test
    func completenessAndEmptyState() {
        let empty = AppStoreConnectCredentials()
        #expect(empty.isEmpty)
        #expect(!empty.isComplete)

        let complete = AppStoreConnectCredentials(
            keyID: "ABC123",
            issuerID: "00000000-0000-0000-0000-000000000000",
            privateKeyPEM: "-----BEGIN PRIVATE KEY-----\\nABC\\n-----END PRIVATE KEY-----"
        )

        #expect(!complete.isEmpty)
        #expect(complete.isComplete)
    }

    @Test
    func trimmedRemovesWhitespace() {
        let credentials = AppStoreConnectCredentials(
            keyID: "  KEYID  ",
            issuerID: "  ISSUER  ",
            privateKeyPEM: "  PEM  "
        )

        let trimmed = credentials.trimmed()

        #expect(trimmed.keyID == "KEYID")
        #expect(trimmed.issuerID == "ISSUER")
        #expect(trimmed.privateKeyPEM == "PEM")
    }

    @Test
    func codableRoundTrip() throws {
        let credentials = AppStoreConnectCredentials(
            keyID: "key-id",
            issuerID: "issuer-id",
            privateKeyPEM: "pem-content"
        )

        let encoded = try JSONEncoder().encode(credentials)
        let decoded = try JSONDecoder().decode(AppStoreConnectCredentials.self, from: encoded)

        #expect(decoded == credentials)
    }
}
