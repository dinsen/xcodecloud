import Foundation

struct ASCRequestBuilder {
    private nonisolated static let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    nonisolated static func makeAppsProbeRequest(token: String) throws -> URLRequest {
        guard let url = URL(string: "/v1/apps?limit=1", relativeTo: baseURL) else {
            throw AppStoreConnectClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }
}
