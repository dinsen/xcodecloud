import Foundation

protocol LiveStatusDeviceRegistrationAPI {
    func setEndpointURL(_ endpointURL: URL?) async
    func registerDevice(appID: String, deviceToken: String, appBundleID: String) async throws
}

actor LiveStatusDeviceRegistrationClient: LiveStatusDeviceRegistrationAPI {
    private let session: URLSession
    private var endpointURL: URL?

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setEndpointURL(_ endpointURL: URL?) async {
        self.endpointURL = endpointURL
    }

    func registerDevice(appID: String, deviceToken: String, appBundleID: String) async throws {
        guard let endpointURL else {
            throw LiveStatusDeviceRegistrationError.missingEndpoint
        }

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let payload = RegistrationPayload(
            appID: appID,
            deviceToken: deviceToken,
            appBundleID: appBundleID
        )
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LiveStatusDeviceRegistrationError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw LiveStatusDeviceRegistrationError.httpError(httpResponse.statusCode)
        }
    }
}

enum LiveStatusDeviceRegistrationError: LocalizedError {
    case missingEndpoint
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .missingEndpoint:
            return "Live Activity device registration endpoint URL is not configured."
        case .invalidResponse:
            return "Live Activity device registration endpoint returned an invalid response."
        case .httpError(let statusCode):
            return "Live Activity device registration endpoint returned HTTP \(statusCode)."
        }
    }
}

private nonisolated struct RegistrationPayload: Encodable {
    let appID: String
    let deviceToken: String
    let appBundleID: String

    enum CodingKeys: String, CodingKey {
        case appID = "appId"
        case deviceToken
        case appBundleID = "appBundleId"
    }
}
