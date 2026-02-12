import Testing
@testable import xcodecloud

@MainActor
struct SettingsViewModelTests {
    @Test
    func loadDoesNotTriggerAutosave() {
        let store = MockCredentialsStore()
        store.storedCredentials = AppStoreConnectCredentials(
            keyID: "saved-key",
            issuerID: "saved-issuer",
            privateKeyPEM: "saved-pem"
        )

        let viewModel = SettingsViewModel(
            credentialsStore: store,
            apiClient: MockAppStoreConnectAPI()
        )

        viewModel.load()

        #expect(viewModel.keyID == "saved-key")
        #expect(store.saveCallCount == 0)
        #expect(store.deleteCallCount == 0)
    }

    @Test
    func autoSavePersistsTrimmedCredentials() {
        let store = MockCredentialsStore()
        let viewModel = SettingsViewModel(
            credentialsStore: store,
            apiClient: MockAppStoreConnectAPI()
        )

        viewModel.load()
        viewModel.keyID = "  key-id  "
        viewModel.issuerID = "  issuer-id  "
        viewModel.privateKeyPEM = "  private-key  "

        viewModel.autoSave()

        #expect(store.saveCallCount == 1)
        #expect(store.storedCredentials?.keyID == "key-id")
        #expect(store.storedCredentials?.issuerID == "issuer-id")
        #expect(store.storedCredentials?.privateKeyPEM == "private-key")
    }

    @Test
    func autoSaveDeletesWhenEmpty() {
        let store = MockCredentialsStore()
        let viewModel = SettingsViewModel(
            credentialsStore: store,
            apiClient: MockAppStoreConnectAPI()
        )

        viewModel.load()
        viewModel.keyID = " "
        viewModel.issuerID = " "
        viewModel.privateKeyPEM = " "

        viewModel.autoSave()

        #expect(store.deleteCallCount == 1)
        #expect(viewModel.saveState == .cleared)
    }

    @Test
    func testConnectionSuccess() async {
        let api = MockAppStoreConnectAPI()
        api.result = .success(())

        let viewModel = SettingsViewModel(
            credentialsStore: MockCredentialsStore(),
            apiClient: api
        )

        viewModel.load()
        viewModel.keyID = "key-id"
        viewModel.issuerID = "issuer-id"
        viewModel.privateKeyPEM = "private-key"

        await viewModel.testConnection()

        #expect(viewModel.connectionSucceeded)
        #expect(viewModel.connectionMessage == "Connection successful.")
        #expect(api.receivedCredentials?.keyID == "key-id")
    }

    @Test
    func testConnectionFailureIsSanitized() async {
        let api = MockAppStoreConnectAPI()
        api.result = .failure(AppStoreConnectClientError.httpError(401))

        let viewModel = SettingsViewModel(
            credentialsStore: MockCredentialsStore(),
            apiClient: api
        )

        viewModel.load()
        viewModel.keyID = "key-id"
        viewModel.issuerID = "issuer-id"
        viewModel.privateKeyPEM = "private-key"

        await viewModel.testConnection()

        #expect(!viewModel.connectionSucceeded)
        #expect(viewModel.connectionMessage == "Authentication failed. Check key ID, issuer ID, private key, and API key permissions.")
    }

    @Test
    func credentialsStoreProtocolContractWithMock() throws {
        let mock = MockCredentialsStore()
        let store: CredentialsStore = mock

        let credentials = AppStoreConnectCredentials(
            keyID: "A",
            issuerID: "B",
            privateKeyPEM: "C"
        )

        try store.saveCredentials(credentials)
        #expect(store.loadCredentials() == credentials)

        store.deleteCredentials()
        #expect(store.loadCredentials() == nil)
    }
}

private final class MockCredentialsStore: CredentialsStore {
    var storedCredentials: AppStoreConnectCredentials?
    var saveCallCount = 0
    var deleteCallCount = 0

    func loadCredentials() -> AppStoreConnectCredentials? {
        storedCredentials
    }

    func saveCredentials(_ credentials: AppStoreConnectCredentials) throws {
        saveCallCount += 1
        storedCredentials = credentials
    }

    func deleteCredentials() {
        deleteCallCount += 1
        storedCredentials = nil
    }
}

private final class MockAppStoreConnectAPI: AppStoreConnectAPI {
    var result: Result<Void, Error> = .success(())
    var receivedCredentials: AppStoreConnectCredentials?

    func testConnection(credentials: AppStoreConnectCredentials) async throws {
        receivedCredentials = credentials

        switch result {
        case .success:
            return
        case .failure(let error):
            throw error
        }
    }

    func fetchApps(credentials: AppStoreConnectCredentials) async throws -> [ASCAppSummary] {
        []
    }

    func fetchPortfolioBuildRuns(credentials: AppStoreConnectCredentials, limit: Int) async throws -> [BuildRunSummary] {
        []
    }

    func fetchLatestBuildRuns(credentials: AppStoreConnectCredentials, appID: String, limit: Int) async throws -> [BuildRunSummary] {
        []
    }

    func fetchWorkflows(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIWorkflowSummary] {
        []
    }

    func triggerBuild(credentials: AppStoreConnectCredentials, appID: String, workflowID: String, clean: Bool) async throws {}

    func fetchBuildRunDiagnostics(credentials: AppStoreConnectCredentials, runID: String) async throws -> BuildRunDiagnostics {
        BuildRunDiagnostics(actions: [])
    }

    func setWorkflowEnabled(credentials: AppStoreConnectCredentials, workflowID: String, isEnabled: Bool) async throws {}

    func deleteWorkflow(credentials: AppStoreConnectCredentials, workflowID: String) async throws {}

    func duplicateWorkflow(credentials: AppStoreConnectCredentials, workflowID: String, newName: String) async throws {}

    func fetchCompatibilityMatrix(credentials: AppStoreConnectCredentials) async throws -> CICompatibilityMatrix {
        CICompatibilityMatrix(xcodeVersions: [])
    }

    func fetchRepositories(credentials: AppStoreConnectCredentials, appID: String) async throws -> [CIRepositorySummary] {
        []
    }
}
