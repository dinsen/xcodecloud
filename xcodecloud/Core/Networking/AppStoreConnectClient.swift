import Foundation

protocol AppStoreConnectAPI {
    func testConnection(credentials: AppStoreConnectCredentials) async throws
    func fetchApps(credentials: AppStoreConnectCredentials) async throws -> [ASCAppSummary]
    func fetchLatestBuildRuns(credentials: AppStoreConnectCredentials, appID: String, limit: Int) async throws -> [BuildRunSummary]
    func fetchWorkflows(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIWorkflowSummary]
    func triggerBuild(credentials: AppStoreConnectCredentials, appID: String, workflowID: String, clean: Bool) async throws
}

actor AppStoreConnectClient: AppStoreConnectAPI {
    private let session: URLSession
    private let tokenFactory: JWTTokenFactory
    private let decoder: JSONDecoder

    init(session: URLSession, tokenFactory: JWTTokenFactory) {
        self.session = session
        self.tokenFactory = tokenFactory

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    init() {
        self.session = .shared
        self.tokenFactory = JWTTokenFactory()

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func testConnection(credentials: AppStoreConnectCredentials) async throws {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makeAppsProbeRequest(token: token)
        _ = try await performRequest(request)
    }

    func fetchApps(credentials: AppStoreConnectCredentials) async throws -> [ASCAppSummary] {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makeAppsListRequest(token: token)
        let data = try await performRequest(request)

        let response = try decoder.decode(AppListResponse.self, from: data)

        return response.data
            .map { ASCAppSummary(id: $0.id, name: $0.attributes.name, bundleID: $0.attributes.bundleID) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func fetchLatestBuildRuns(credentials: AppStoreConnectCredentials, appID: String, limit: Int) async throws -> [BuildRunSummary] {
        let token = try makeToken(from: credentials)
        let productID = try await fetchCIProductID(token: token, appID: appID)

        let request = try ASCRequestBuilder.makeBuildRunsRequest(
            token: token,
            productID: productID,
            limit: limit
        )

        let data = try await performRequest(request)
        let response = try decoder.decode(BuildRunListResponse.self, from: data)

        var workflowByID: [String: String] = [:]
        var branchByID: [String: String] = [:]

        for resource in response.included ?? [] {
            if resource.type == "ciWorkflows", let name = resource.attributes?.name {
                workflowByID[resource.id] = name
            }
            if resource.type == "scmGitReferences" {
                if let canonicalName = resource.attributes?.canonicalName {
                    branchByID[resource.id] = canonicalName
                } else if let name = resource.attributes?.name {
                    branchByID[resource.id] = name
                }
            }
        }

        return response.data
            .map { resource in
                let workflowID = resource.relationships?.workflow?.data?.id
                let workflowName = workflowID.flatMap { workflowByID[$0] } ?? "Unknown Workflow"

                let branchID = resource.relationships?.sourceBranchOrTag?.data?.id
                let branchName = branchID.flatMap { branchByID[$0] }

                let issueCounts = BuildIssueCounts(
                    errors: resource.attributes.issueCounts?.errors ?? 0,
                    warnings: resource.attributes.issueCounts?.warnings ?? 0,
                    testFailures: resource.attributes.issueCounts?.testFailures ?? 0,
                    analyzerWarnings: resource.attributes.issueCounts?.analyzerWarnings ?? 0
                )

                return BuildRunSummary(
                    id: resource.id,
                    number: resource.attributes.number,
                    workflowName: workflowName,
                    status: BuildStatus.derive(
                        executionProgress: resource.attributes.executionProgress,
                        completionStatus: resource.attributes.completionStatus
                    ),
                    executionProgress: resource.attributes.executionProgress,
                    completionStatus: resource.attributes.completionStatus,
                    createdDate: resource.attributes.createdDate,
                    startedDate: resource.attributes.startedDate,
                    finishedDate: resource.attributes.finishedDate,
                    sourceBranch: branchName,
                    sourceCommitSHA: resource.attributes.sourceCommit?.commitSHA,
                    sourceCommitMessage: resource.attributes.sourceCommit?.message,
                    sourceCommitWebURL: resource.attributes.sourceCommit?.webURL,
                    buildWebURL: resource.links?.selfURL,
                    issueCounts: issueCounts
                )
            }
            .sorted { lhs, rhs in
                if let lhsNumber = lhs.number, let rhsNumber = rhs.number {
                    return lhsNumber > rhsNumber
                }

                let lhsDate = lhs.timestamp ?? .distantPast
                let rhsDate = rhs.timestamp ?? .distantPast
                return lhsDate > rhsDate
            }
    }

    func fetchWorkflows(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIWorkflowSummary] {
        let token = try makeToken(from: credentials)
        let productID = try await fetchCIProductID(token: token, appID: appID)
        let request = try ASCRequestBuilder.makeWorkflowsRequest(token: token, productID: productID)
        let data = try await performRequest(request)
        let response = try decoder.decode(WorkflowListResponse.self, from: data)

        var repositoryNames: [String: String] = [:]
        var xcodeNames: [String: String] = [:]
        var macOSNames: [String: String] = [:]

        for resource in response.included ?? [] {
            if resource.type == "scmRepositories" {
                let owner = resource.attributes?.ownerName ?? ""
                let name = resource.attributes?.repositoryName ?? ""
                let display = [owner, name]
                    .filter { !$0.isEmpty }
                    .joined(separator: "/")
                if !display.isEmpty {
                    repositoryNames[resource.id] = display
                }
            } else if resource.type == "ciXcodeVersions" {
                if let name = resource.attributes?.name {
                    xcodeNames[resource.id] = name
                } else if let version = resource.attributes?.version {
                    xcodeNames[resource.id] = version
                }
            } else if resource.type == "ciMacOsVersions" {
                if let name = resource.attributes?.name {
                    macOSNames[resource.id] = name
                } else if let version = resource.attributes?.version {
                    macOSNames[resource.id] = version
                }
            }
        }

        return response.data
            .map { workflow in
                let repositoryID = workflow.relationships?.repository?.data?.id
                let xcodeVersionID = workflow.relationships?.xcodeVersion?.data?.id
                let macOSVersionID = workflow.relationships?.macOsVersion?.data?.id

                return CIWorkflowSummary(
                    id: workflow.id,
                    name: workflow.attributes.name,
                    isEnabled: workflow.attributes.isEnabled ?? false,
                    isLockedForEditing: workflow.attributes.isLockedForEditing ?? false,
                    cleanByDefault: workflow.attributes.clean ?? false,
                    repositoryName: repositoryID.flatMap { repositoryNames[$0] },
                    xcodeVersion: xcodeVersionID.flatMap { xcodeNames[$0] },
                    macOSVersion: macOSVersionID.flatMap { macOSNames[$0] },
                    lastModifiedDate: workflow.attributes.lastModifiedDate
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func triggerBuild(credentials: AppStoreConnectCredentials, appID: String, workflowID: String, clean: Bool) async throws {
        let token = try makeToken(from: credentials)
        _ = try await fetchCIProductID(token: token, appID: appID)
        let request = try ASCRequestBuilder.makeCreateBuildRunRequest(
            token: token,
            workflowID: workflowID,
            clean: clean
        )
        _ = try await performRequest(request)
    }

    private func fetchCIProductID(token: String, appID: String) async throws -> String {
        let request = try ASCRequestBuilder.makeCIProductRequest(token: token, appID: appID)
        let data = try await performRequest(request)
        let response = try decoder.decode(CIProductResponse.self, from: data)
        return response.data.id
    }

    private func makeToken(from credentials: AppStoreConnectCredentials) throws -> String {
        let trimmed = credentials.trimmed()
        guard trimmed.isComplete else {
            throw AppStoreConnectClientError.missingCredentials
        }

        return try tokenFactory.makeToken(credentials: trimmed)
    }

    private func performRequest(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppStoreConnectClientError.invalidResponse
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            if let decodedError = try? decoder.decode(AppStoreConnectAPIErrorResponse.self, from: data),
               let firstError = decodedError.errors.first {
                throw AppStoreConnectClientError.apiError(
                    statusCode: httpResponse.statusCode,
                    message: firstError.title
                )
            }
            throw AppStoreConnectClientError.httpError(httpResponse.statusCode)
        }

        return data
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
        case 404:
            return "The selected app or Xcode Cloud product could not be found."
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

private nonisolated struct AppListResponse: Decodable {
    let data: [AppResource]
}

private nonisolated struct AppResource: Decodable {
    let id: String
    let attributes: AppAttributes
}

private nonisolated struct AppAttributes: Decodable {
    let name: String
    let bundleID: String

    enum CodingKeys: String, CodingKey {
        case name
        case bundleID = "bundleId"
    }
}

private nonisolated struct CIProductResponse: Decodable {
    let data: CIProductResource
}

private nonisolated struct CIProductResource: Decodable {
    let id: String
}

private nonisolated struct BuildRunListResponse: Decodable {
    let data: [BuildRunResource]
    let included: [BuildRunIncludedResource]?
}

private nonisolated struct BuildRunResource: Decodable {
    let id: String
    let attributes: BuildRunAttributes
    let relationships: BuildRunRelationships?
    let links: BuildRunLinks?
}

private nonisolated struct BuildRunAttributes: Decodable {
    let number: Int?
    let createdDate: Date?
    let startedDate: Date?
    let finishedDate: Date?
    let sourceCommit: SourceCommit?
    let issueCounts: IssueCounts?
    let executionProgress: String?
    let completionStatus: String?
}

private nonisolated struct SourceCommit: Decodable {
    let commitSHA: String?
    let message: String?
    let webURL: URL?

    enum CodingKeys: String, CodingKey {
        case commitSHA = "commitSha"
        case message
        case webURL = "webUrl"
    }
}

private nonisolated struct IssueCounts: Decodable {
    let errors: Int?
    let warnings: Int?
    let testFailures: Int?
    let analyzerWarnings: Int?
}

private nonisolated struct BuildRunRelationships: Decodable {
    let workflow: RelationshipContainer?
    let sourceBranchOrTag: RelationshipContainer?
}

private nonisolated struct RelationshipContainer: Decodable {
    let data: RelationshipData?
}

private nonisolated struct RelationshipData: Decodable {
    let id: String
}

private nonisolated struct BuildRunLinks: Decodable {
    let selfURL: URL?

    enum CodingKeys: String, CodingKey {
        case selfURL = "self"
    }
}

private nonisolated struct BuildRunIncludedResource: Decodable {
    let id: String
    let type: String
    let attributes: IncludedAttributes?
}

private nonisolated struct WorkflowListResponse: Decodable {
    let data: [WorkflowResource]
    let included: [WorkflowIncludedResource]?
}

private nonisolated struct WorkflowResource: Decodable {
    let id: String
    let attributes: WorkflowAttributes
    let relationships: WorkflowRelationships?
}

private nonisolated struct WorkflowAttributes: Decodable {
    let name: String
    let isEnabled: Bool?
    let isLockedForEditing: Bool?
    let clean: Bool?
    let lastModifiedDate: Date?
}

private nonisolated struct WorkflowRelationships: Decodable {
    let repository: RelationshipContainer?
    let xcodeVersion: RelationshipContainer?
    let macOsVersion: RelationshipContainer?
}

private nonisolated struct WorkflowIncludedResource: Decodable {
    let id: String
    let type: String
    let attributes: WorkflowIncludedAttributes?
}

private nonisolated struct WorkflowIncludedAttributes: Decodable {
    let name: String?
    let version: String?
    let ownerName: String?
    let repositoryName: String?
}

private nonisolated struct IncludedAttributes: Decodable {
    let name: String?
    let canonicalName: String?
}
