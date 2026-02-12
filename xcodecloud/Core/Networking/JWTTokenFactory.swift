import CryptoKit
import Foundation

struct JWTTokenFactory {
    nonisolated func makeToken(
        credentials: AppStoreConnectCredentials,
        now: Date = Date(),
        lifetime: TimeInterval = 20 * 60
    ) throws -> String {
        let nowSeconds = Int(now.timeIntervalSince1970)
        let expiration = nowSeconds + Int(lifetime)

        let header: [String: String] = [
            "alg": "ES256",
            "kid": credentials.keyID,
            "typ": "JWT",
        ]

        let payload: [String: Any] = [
            "iss": credentials.issuerID,
            "iat": nowSeconds,
            "exp": expiration,
            "aud": "appstoreconnect-v1",
        ]

        let headerData = try JSONSerialization.data(withJSONObject: header)
        let payloadData = try JSONSerialization.data(withJSONObject: payload)

        let headerPart = headerData.base64URLEncodedString()
        let payloadPart = payloadData.base64URLEncodedString()
        let message = "\(headerPart).\(payloadPart)"

        let privateKey = try parsePrivateKey(credentials.privateKeyPEM)
        let signature = try sign(message: message, privateKey: privateKey)

        return "\(message).\(signature.base64URLEncodedString())"
    }

    private nonisolated func parsePrivateKey(_ pemString: String) throws -> P256.Signing.PrivateKey {
        let cleaned = pemString
            .replacingOccurrences(of: "-----BEGIN PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----BEGIN EC PRIVATE KEY-----", with: "")
            .replacingOccurrences(of: "-----END EC PRIVATE KEY-----", with: "")
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()

        guard let keyData = Data(base64Encoded: cleaned) else {
            throw AppStoreConnectClientError.invalidPrivateKey
        }

        do {
            return try P256.Signing.PrivateKey(derRepresentation: keyData)
        } catch {
            throw AppStoreConnectClientError.invalidPrivateKey
        }
    }

    private nonisolated func sign(message: String, privateKey: P256.Signing.PrivateKey) throws -> Data {
        guard let messageData = message.data(using: .utf8) else {
            throw AppStoreConnectClientError.signingFailed
        }

        do {
            return try privateKey.signature(for: messageData).rawRepresentation
        } catch {
            throw AppStoreConnectClientError.signingFailed
        }
    }
}

private extension Data {
    nonisolated func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
