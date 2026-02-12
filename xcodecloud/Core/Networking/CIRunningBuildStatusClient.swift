import Foundation

protocol CIRunningBuildStatusAPI {
    func fetchStatus(endpointURL: URL, appID: String) async throws -> CIRunningBuildStatus
}

actor CIRunningBuildStatusClient: CIRunningBuildStatusAPI {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func fetchStatus(endpointURL: URL, appID: String) async throws -> CIRunningBuildStatus {
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw CIRunningBuildStatusClientError.invalidEndpoint
        }

        var queryItems = components.queryItems ?? []
        queryItems.removeAll(where: { $0.name == "appId" })
        queryItems.append(URLQueryItem(name: "appId", value: appID))
        components.queryItems = queryItems

        guard let url = components.url else {
            throw CIRunningBuildStatusClientError.invalidEndpoint
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw CIRunningBuildStatusClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw CIRunningBuildStatusClientError.httpError(httpResponse.statusCode)
        }

        let parsedResponse = try decoder.decode(CIRunningBuildStatusResponse.self, from: data)
        return CIRunningBuildStatus(
            buildsRunning: parsedResponse.buildsRunning,
            runningCount: parsedResponse.runningCount,
            checkedAt: parsedResponse.checkedAt
        )
    }
}

enum CIRunningBuildStatusClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Live status endpoint URL is invalid."
        case .invalidResponse:
            return "Live status endpoint returned an invalid response."
        case .httpError(let statusCode):
            return "Live status endpoint returned HTTP \(statusCode)."
        }
    }
}

private nonisolated struct CIRunningBuildStatusResponse: Decodable {
    let buildsRunning: Bool
    let runningCount: Int
    let checkedAt: Date?
}
