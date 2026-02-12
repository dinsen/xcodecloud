import Foundation

protocol AppStoreConnectAPI {
    func testConnection(credentials: AppStoreConnectCredentials) async throws
}

actor AppStoreConnectClient: AppStoreConnectAPI {
    private let session: URLSession
    private let tokenFactory: JWTTokenFactory

    init(session: URLSession, tokenFactory: JWTTokenFactory) {
        self.session = session
        self.tokenFactory = tokenFactory
    }

    init() {
        self.session = .shared
        self.tokenFactory = JWTTokenFactory()
    }

    func testConnection(credentials: AppStoreConnectCredentials) async throws {
        let trimmed = credentials.trimmed()
        guard trimmed.isComplete else {
            throw AppStoreConnectClientError.missingCredentials
        }

        let token = try tokenFactory.makeToken(credentials: trimmed)
        let request = try ASCRequestBuilder.makeAppsProbeRequest(token: token)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? JSONDecoder().decode(AppStoreConnectAPIErrorResponse.self, from: data),
               let firstError = decodedError.errors.first {
                throw AppStoreConnectClientError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: firstError.title
                )
            }
            throw AppStoreConnectClientError.httpError(httpResponse.statusCode)
        }
    }
}

enum AppStoreConnectClientError: LocalizedError {
    case missingCredentials
    case invalidPrivateKey
    case signingFailed
    case invalidURL
    case invalidResponse
    case httpError(Int)
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "All fields are required."
        case .invalidPrivateKey:
            return "Private key format is invalid. Paste the full .p8 content including BEGIN/END lines."
        case .signingFailed:
            return "Could not sign JWT with the provided private key."
        case .invalidURL, .invalidResponse:
            return "Unable to contact App Store Connect right now."
        case .httpError(let code):
            return Self.userSafeHTTPMessage(for: code)
        case .apiError(let code, _):
            return Self.userSafeHTTPMessage(for: code)
        }
    }

    private static func userSafeHTTPMessage(for statusCode: Int) -> String {
        switch statusCode {
        case 401, 403:
            return "Authentication failed. Check key ID, issuer ID, private key, and API key permissions."
        case 429:
            return "Rate limit reached. Please try again in a moment."
        default:
            return "App Store Connect request failed (HTTP \(statusCode))."
        }
    }
}

private nonisolated struct AppStoreConnectAPIErrorResponse: Decodable {
    let errors: [AppStoreConnectAPIError]
}

private nonisolated struct AppStoreConnectAPIError: Decodable {
    let status: String
    let code: String
    let title: String
    let detail: String
}
