import Foundation

protocol AppStoreConnectAPI {
    func testConnection(credentials: AppStoreConnectCredentials) async throws
    func fetchApps(credentials: AppStoreConnectCredentials) async throws -> [ASCAppSummary]
    func fetchPortfolioBuildRuns(credentials: AppStoreConnectCredentials, limit: Int) async throws -> [BuildRunSummary]
    func fetchLatestBuildRuns(credentials: AppStoreConnectCredentials, appID: String, limit: Int) async throws -> [BuildRunSummary]
    func fetchWorkflows(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIWorkflowSummary]
    func triggerBuild(credentials: AppStoreConnectCredentials, appID: String, workflowID: String, clean: Bool) async throws
    func fetchBuildRunDiagnostics(credentials: AppStoreConnectCredentials, runID: String) async throws -> BuildRunDiagnostics
    func setWorkflowEnabled(credentials: AppStoreConnectCredentials, workflowID: String, isEnabled: Bool) async throws
    func deleteWorkflow(credentials: AppStoreConnectCredentials, workflowID: String) async throws
    func duplicateWorkflow(credentials: AppStoreConnectCredentials, workflowID: String, newName: String) async throws
    func fetchCompatibilityMatrix(credentials: AppStoreConnectCredentials) async throws -> CICompatibilityMatrix
    func fetchRepositories(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIRepositorySummary]
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

    func fetchPortfolioBuildRuns(credentials: AppStoreConnectCredentials, limit: Int) async throws -> [BuildRunSummary] {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makePortfolioBuildRunsRequest(token: token, limit: limit)
        let data = try await performRequest(request)
        let response = try decoder.decode(BuildRunListResponse.self, from: data)
        return mapBuildRuns(response, sortByBuildNumber: false)
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
        return mapBuildRuns(response, sortByBuildNumber: true)
    }

    private func mapBuildRuns(_ response: BuildRunListResponse, sortByBuildNumber: Bool) -> [BuildRunSummary] {
        var workflowByID: [String: String] = [:]
        var branchByID: [String: String] = [:]
        var appByProductID: [String: ASCAppSummary] = [:]

        for resource in response.included ?? [] {
            if resource.type == "ciWorkflows", let name = resource.attributes?.name {
                workflowByID[resource.id] = name
            }

            if resource.type == "ciProducts" {
                let appName = resource.attributes?.name ?? "Unknown App"
                let bundleID = resource.attributes?.bundleID ?? "-"
                appByProductID[resource.id] = ASCAppSummary(
                    id: resource.id,
                    name: appName,
                    bundleID: bundleID
                )
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
                let productID = resource.relationships?.product?.data?.id
                let app = productID.flatMap { appByProductID[$0] }

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
                    app: app,
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
                if sortByBuildNumber, let lhsNumber = lhs.number, let rhsNumber = rhs.number {
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

    func fetchBuildRunDiagnostics(credentials: AppStoreConnectCredentials, runID: String) async throws -> BuildRunDiagnostics {
        let token = try makeToken(from: credentials)
        let actionsRequest = try ASCRequestBuilder.makeBuildActionsRequest(token: token, runID: runID)
        let actionsData = try await performRequest(actionsRequest)
        let actionsResponse = try decoder.decode(BuildActionListResponse.self, from: actionsData)

        var diagnostics: [BuildActionDiagnostics] = []

        for action in actionsResponse.data {
            async let issuesTask = fetchIssues(token: token, actionID: action.id)
            async let testsTask = fetchTestResults(token: token, actionID: action.id)
            async let artifactsTask = fetchArtifacts(token: token, actionID: action.id)

            let issues = try await issuesTask
            let tests = try await testsTask
            let artifacts = try await artifactsTask

            let issueCounts = BuildIssueCounts(
                errors: action.attributes.issueCounts?.errors ?? 0,
                warnings: action.attributes.issueCounts?.warnings ?? 0,
                testFailures: action.attributes.issueCounts?.testFailures ?? 0,
                analyzerWarnings: action.attributes.issueCounts?.analyzerWarnings ?? 0
            )

            diagnostics.append(
                BuildActionDiagnostics(
                    id: action.id,
                    name: action.attributes.name ?? "Unknown Action",
                    actionType: action.attributes.actionType,
                    executionProgress: action.attributes.executionProgress,
                    completionStatus: action.attributes.completionStatus,
                    startedDate: action.attributes.startedDate,
                    finishedDate: action.attributes.finishedDate,
                    issueCounts: issueCounts,
                    issues: issues,
                    testResults: tests,
                    artifacts: artifacts
                )
            )
        }

        let sorted = diagnostics.sorted {
            let lhsDate = $0.startedDate ?? .distantPast
            let rhsDate = $1.startedDate ?? .distantPast
            return lhsDate < rhsDate
        }

        return BuildRunDiagnostics(actions: sorted)
    }

    func setWorkflowEnabled(credentials: AppStoreConnectCredentials, workflowID: String, isEnabled: Bool) async throws {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makeWorkflowUpdateRequest(
            token: token,
            workflowID: workflowID,
            isEnabled: isEnabled
        )
        _ = try await performRequest(request)
    }

    func deleteWorkflow(credentials: AppStoreConnectCredentials, workflowID: String) async throws {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makeWorkflowDeleteRequest(token: token, workflowID: workflowID)
        _ = try await performRequest(request)
    }

    func duplicateWorkflow(credentials: AppStoreConnectCredentials, workflowID: String, newName: String) async throws {
        let token = try makeToken(from: credentials)
        let detailRequest = try ASCRequestBuilder.makeWorkflowDetailRequest(token: token, workflowID: workflowID)
        let detailData = try await performRequest(detailRequest)

        guard let payload = try JSONSerialization.jsonObject(with: detailData) as? [String: Any],
              let data = payload["data"] as? [String: Any],
              let attributes = data["attributes"] as? [String: Any],
              let relationships = data["relationships"] as? [String: Any] else {
            throw AppStoreConnectClientError.invalidResponse
        }

        let actions = normalizedJSONValue(attributes["actions"]) as? [[String: Any]] ?? []
        let description = normalizedJSONValue(attributes["description"]) as? String ?? "Cloned workflow"
        let clean = normalizedJSONValue(attributes["clean"]) as? Bool ?? false
        let isEnabled = normalizedJSONValue(attributes["isEnabled"]) as? Bool ?? true
        let originalPath = normalizedJSONValue(attributes["containerFilePath"]) as? String ?? ".xcodecloud/workflows/default.xcworkflow"
        let containerFilePath = makeWorkflowContainerPath(from: originalPath, name: newName)

        guard let productID = relationshipID(in: relationships, key: "product"),
              let repositoryID = relationshipID(in: relationships, key: "repository"),
              let xcodeVersionID = relationshipID(in: relationships, key: "xcodeVersion"),
              let macOSVersionID = relationshipID(in: relationships, key: "macOsVersion") else {
            throw AppStoreConnectClientError.invalidResponse
        }

        var createAttributes: [String: Any] = [
            "name": newName,
            "description": description,
            "actions": actions,
            "isEnabled": isEnabled,
            "clean": clean,
            "containerFilePath": containerFilePath,
        ]

        for key in [
            "branchStartCondition",
            "tagStartCondition",
            "pullRequestStartCondition",
            "scheduledStartCondition",
            "manualBranchStartCondition",
            "manualTagStartCondition",
            "manualPullRequestStartCondition",
        ] {
            if let value = normalizedJSONValue(attributes[key]) {
                createAttributes[key] = value
            }
        }

        let requestBody: [String: Any] = [
            "data": [
                "type": "ciWorkflows",
                "attributes": createAttributes,
                "relationships": [
                    "product": [
                        "data": [
                            "type": "ciProducts",
                            "id": productID,
                        ],
                    ],
                    "repository": [
                        "data": [
                            "type": "scmRepositories",
                            "id": repositoryID,
                        ],
                    ],
                    "xcodeVersion": [
                        "data": [
                            "type": "ciXcodeVersions",
                            "id": xcodeVersionID,
                        ],
                    ],
                    "macOsVersion": [
                        "data": [
                            "type": "ciMacOsVersions",
                            "id": macOSVersionID,
                        ],
                    ],
                ],
            ],
        ]

        let requestData = try JSONSerialization.data(withJSONObject: requestBody, options: [])
        let request = try ASCRequestBuilder.makeWorkflowCreateRequest(token: token, body: requestData)
        _ = try await performRequest(request)
    }

    func fetchCompatibilityMatrix(credentials: AppStoreConnectCredentials) async throws -> CICompatibilityMatrix {
        let token = try makeToken(from: credentials)
        let request = try ASCRequestBuilder.makeCIXcodeVersionsRequest(token: token)
        let data = try await performRequest(request)
        let response = try decoder.decode(XcodeVersionListResponse.self, from: data)

        var macOSByID: [String: String] = [:]
        for included in response.included ?? [] {
            let displayName = included.attributes.name ?? included.attributes.version ?? "Unknown"
            macOSByID[included.id] = displayName
        }

        let unsorted: [CIXcodeCompatibility] = response.data.map { resource in
            let name = resource.attributes.name ?? resource.attributes.version ?? "Unknown"
            let macIDs = resource.relationships?.macOsVersions?.data?.map(\.id) ?? []
            let compatible = macIDs.compactMap { macOSByID[$0] }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

            return CIXcodeCompatibility(
                id: resource.id,
                name: name,
                version: resource.attributes.version,
                compatibleMacOSVersions: compatible
            )
        }
        let xcodeVersions = unsorted.sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedDescending
        }

        return CICompatibilityMatrix(xcodeVersions: xcodeVersions)
    }

    func fetchRepositories(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIRepositorySummary] {
        let token = try makeToken(from: credentials)
        let productID = try await fetchCIProductID(token: token, appID: appID)

        async let primaryDataTask: Data = {
            let request = try ASCRequestBuilder.makePrimaryRepositoriesRequest(token: token, productID: productID)
            return try await performRequest(request)
        }()

        async let additionalDataTask: Data = {
            let request = try ASCRequestBuilder.makeAdditionalRepositoriesRequest(token: token, productID: productID)
            return try await performRequest(request)
        }()

        let primaryData = try await primaryDataTask
        let additionalData = try await additionalDataTask

        let primaryResponse = try decoder.decode(ScmRepositoryListResponse.self, from: primaryData)
        let additionalResponse = try decoder.decode(ScmRepositoryListResponse.self, from: additionalData)

        let primary = primaryResponse.data.map { repository in
            mapRepository(repository, isPrimary: true)
        }
        let additional = additionalResponse.data.map { repository in
            mapRepository(repository, isPrimary: false)
        }

        return (primary + additional).sorted { lhs, rhs in
            if lhs.isPrimary != rhs.isPrimary {
                return lhs.isPrimary && !rhs.isPrimary
            }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
    }

    private func fetchIssues(token: String, actionID: String) async throws -> [BuildIssueDiagnostics] {
        let request = try ASCRequestBuilder.makeBuildActionIssuesRequest(token: token, actionID: actionID)
        let data = try await performRequest(request)
        let response = try decoder.decode(BuildIssueListResponse.self, from: data)

        return response.data.map { issue in
            BuildIssueDiagnostics(
                id: issue.id,
                issueType: issue.attributes.issueType,
                category: issue.attributes.category,
                message: issue.attributes.message,
                fileSource: issue.attributes.fileSource
            )
        }
    }

    private func fetchTestResults(token: String, actionID: String) async throws -> [BuildTestResultDiagnostics] {
        let request = try ASCRequestBuilder.makeBuildActionTestResultsRequest(token: token, actionID: actionID)
        let data = try await performRequest(request)
        let response = try decoder.decode(BuildTestResultListResponse.self, from: data)

        return response.data.map { testResult in
            BuildTestResultDiagnostics(
                id: testResult.id,
                className: testResult.attributes.className,
                name: testResult.attributes.name,
                status: testResult.attributes.status,
                message: testResult.attributes.message,
                fileSource: testResult.attributes.fileSource
            )
        }
    }

    private func fetchArtifacts(token: String, actionID: String) async throws -> [BuildArtifactDiagnostics] {
        let request = try ASCRequestBuilder.makeBuildActionArtifactsRequest(token: token, actionID: actionID)
        let data = try await performRequest(request)
        let response = try decoder.decode(BuildArtifactListResponse.self, from: data)

        return response.data.map { artifact in
            BuildArtifactDiagnostics(
                id: artifact.id,
                fileType: artifact.attributes.fileType,
                fileName: artifact.attributes.fileName,
                fileSize: artifact.attributes.fileSize,
                downloadURL: artifact.attributes.downloadURL
            )
        }
    }

    private func relationshipID(in relationships: [String: Any], key: String) -> String? {
        guard let relationship = relationships[key] as? [String: Any],
              let data = relationship["data"] as? [String: Any],
              let id = data["id"] as? String else {
            return nil
        }

        return id
    }

    private func normalizedJSONValue(_ value: Any?) -> Any? {
        guard let value else { return nil }
        if value is NSNull { return nil }
        return value
    }

    private func makeWorkflowContainerPath(from originalPath: String, name: String) -> String {
        let original = NSString(string: originalPath)
        let directory = original.deletingLastPathComponent
        let ext = original.pathExtension
        let slug = workflowSlug(name)
        let fileName = ext.isEmpty ? slug : "\(slug).\(ext)"

        if directory.isEmpty || directory == "." {
            return fileName
        }

        return "\(directory)/\(fileName)"
    }

    private func workflowSlug(_ name: String) -> String {
        let lowercased = name.lowercased()
        let scalarView = lowercased.unicodeScalars.map { scalar -> Character in
            if CharacterSet.alphanumerics.contains(scalar) {
                return Character(scalar)
            }
            return "-"
        }

        let raw = String(scalarView)
        let collapsed = raw.replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
        return collapsed.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private func mapRepository(_ resource: ScmRepositoryResource, isPrimary: Bool) -> CIRepositorySummary {
        let owner = resource.attributes.ownerName
        let name = resource.attributes.repositoryName
        let displayName = [owner, name]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: "/")

        return CIRepositorySummary(
            id: resource.id,
            displayName: displayName.isEmpty ? resource.id : displayName,
            ownerName: owner,
            repositoryName: name,
            provider: resource.attributes.scmProvider,
            defaultBranch: resource.attributes.defaultBranch,
            lastAccessedDate: resource.attributes.lastAccessedDate,
            isPrimary: isPrimary
        )
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
    let product: RelationshipContainer?
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

private nonisolated struct BuildActionListResponse: Decodable {
    let data: [BuildActionResource]
}

private nonisolated struct BuildActionResource: Decodable {
    let id: String
    let attributes: BuildActionAttributes
}

private nonisolated struct BuildActionAttributes: Decodable {
    let name: String?
    let actionType: String?
    let startedDate: Date?
    let finishedDate: Date?
    let issueCounts: IssueCounts?
    let executionProgress: String?
    let completionStatus: String?
}

private nonisolated struct BuildIssueListResponse: Decodable {
    let data: [BuildIssueResource]
}

private nonisolated struct BuildIssueResource: Decodable {
    let id: String
    let attributes: BuildIssueAttributes
}

private nonisolated struct BuildIssueAttributes: Decodable {
    let issueType: String?
    let category: String?
    let message: String?
    let fileSource: String?
}

private nonisolated struct BuildTestResultListResponse: Decodable {
    let data: [BuildTestResultResource]
}

private nonisolated struct BuildTestResultResource: Decodable {
    let id: String
    let attributes: BuildTestResultAttributes
}

private nonisolated struct BuildTestResultAttributes: Decodable {
    let className: String?
    let name: String?
    let status: String?
    let message: String?
    let fileSource: String?
}

private nonisolated struct BuildArtifactListResponse: Decodable {
    let data: [BuildArtifactResource]
}

private nonisolated struct BuildArtifactResource: Decodable {
    let id: String
    let attributes: BuildArtifactAttributes
}

private nonisolated struct BuildArtifactAttributes: Decodable {
    let fileType: String?
    let fileName: String?
    let fileSize: Int?
    let downloadURL: URL?

    enum CodingKeys: String, CodingKey {
        case fileType
        case fileName
        case fileSize
        case downloadURL = "downloadUrl"
    }
}

private nonisolated struct XcodeVersionListResponse: Decodable {
    let data: [XcodeVersionResource]
    let included: [MacOSVersionResource]?
}

private nonisolated struct XcodeVersionResource: Decodable {
    let id: String
    let attributes: VersionAttributes
    let relationships: XcodeVersionRelationships?
}

private nonisolated struct XcodeVersionRelationships: Decodable {
    let macOsVersions: ToManyRelationshipContainer?
}

private nonisolated struct MacOSVersionResource: Decodable {
    let id: String
    let attributes: VersionAttributes
}

private nonisolated struct VersionAttributes: Decodable {
    let name: String?
    let version: String?
}

private nonisolated struct ToManyRelationshipContainer: Decodable {
    let data: [RelationshipData]?
}

private nonisolated struct ScmRepositoryListResponse: Decodable {
    let data: [ScmRepositoryResource]
}

private nonisolated struct ScmRepositoryResource: Decodable {
    let id: String
    let attributes: ScmRepositoryAttributes
}

private nonisolated struct ScmRepositoryAttributes: Decodable {
    let ownerName: String?
    let repositoryName: String?
    let scmProvider: String?
    let defaultBranch: String?
    let lastAccessedDate: Date?
}

private nonisolated struct IncludedAttributes: Decodable {
    let name: String?
    let canonicalName: String?
    let bundleID: String?

    enum CodingKeys: String, CodingKey {
        case name
        case canonicalName
        case bundleID = "bundleId"
    }
}
