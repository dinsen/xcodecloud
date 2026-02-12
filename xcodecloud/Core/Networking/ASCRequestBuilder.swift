import Foundation

struct ASCRequestBuilder {
    private nonisolated static let baseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    nonisolated static func makeAppsProbeRequest(token: String) throws -> URLRequest {
        try makeRequest(path: "/v1/apps", token: token, queryItems: [
            URLQueryItem(name: "limit", value: "1"),
        ])
    }

    nonisolated static func makeAppsListRequest(token: String, limit: Int = 200) throws -> URLRequest {
        try makeRequest(path: "/v1/apps", token: token, queryItems: [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 200)))"),
            URLQueryItem(name: "sort", value: "name"),
            URLQueryItem(name: "fields[apps]", value: "name,bundleId"),
        ])
    }

    nonisolated static func makeCIProductRequest(token: String, appID: String) throws -> URLRequest {
        try makeRequest(path: "/v1/apps/\(appID)/ciProduct", token: token, queryItems: [
            URLQueryItem(name: "fields[ciProducts]", value: "name,bundleId"),
        ])
    }

    nonisolated static func makeBuildRunsRequest(token: String, productID: String, limit: Int) throws -> URLRequest {
        try makeRequest(path: "/v1/ciProducts/\(productID)/buildRuns", token: token, queryItems: [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 200)))"),
            URLQueryItem(name: "sort", value: "-number"),
            URLQueryItem(name: "include", value: "workflow,sourceBranchOrTag"),
            URLQueryItem(name: "fields[ciBuildRuns]", value: "number,createdDate,startedDate,finishedDate,sourceCommit,issueCounts,executionProgress,completionStatus,workflow,sourceBranchOrTag"),
            URLQueryItem(name: "fields[ciWorkflows]", value: "name"),
            URLQueryItem(name: "fields[scmGitReferences]", value: "name,canonicalName"),
        ])
    }

    nonisolated static func makeWorkflowsRequest(token: String, productID: String, limit: Int = 200) throws -> URLRequest {
        try makeRequest(path: "/v1/ciProducts/\(productID)/workflows", token: token, queryItems: [
            URLQueryItem(name: "limit", value: "\(max(1, min(limit, 200)))"),
            URLQueryItem(name: "include", value: "repository,xcodeVersion,macOsVersion"),
            URLQueryItem(name: "fields[ciWorkflows]", value: "name,isEnabled,isLockedForEditing,clean,lastModifiedDate,repository,xcodeVersion,macOsVersion"),
            URLQueryItem(name: "fields[scmRepositories]", value: "ownerName,repositoryName"),
            URLQueryItem(name: "fields[ciXcodeVersions]", value: "name,version"),
            URLQueryItem(name: "fields[ciMacOsVersions]", value: "name,version"),
        ])
    }

    nonisolated static func makeCreateBuildRunRequest(token: String, workflowID: String, clean: Bool) throws -> URLRequest {
        let body: [String: Any] = [
            "data": [
                "type": "ciBuildRuns",
                "attributes": [
                    "clean": clean,
                ],
                "relationships": [
                    "workflow": [
                        "data": [
                            "type": "ciWorkflows",
                            "id": workflowID,
                        ],
                    ],
                ],
            ],
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: body, options: [])

        return try makeRequest(
            path: "/v1/ciBuildRuns",
            token: token,
            method: "POST",
            body: bodyData
        )
    }

    private nonisolated static func makeRequest(
        path: String,
        token: String,
        queryItems: [URLQueryItem] = [],
        method: String = "GET",
        body: Data? = nil
    ) throws -> URLRequest {
        guard let basePathURL = URL(string: path, relativeTo: baseURL),
              var components = URLComponents(url: basePathURL, resolvingAgainstBaseURL: true) else {
            throw AppStoreConnectClientError.invalidURL
        }

        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw AppStoreConnectClientError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}
