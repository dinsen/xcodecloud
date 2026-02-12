import Foundation
import Observation

@MainActor
@Observable
final class SettingsViewModel {
    enum SaveState: Equatable {
        case idle
        case saved
        case cleared
        case failed(String)
    }

    var keyID: String = ""
    var issuerID: String = ""
    var privateKeyPEM: String = ""

    var isTestingConnection = false
    var connectionMessage: String?
    var connectionSucceeded = false
    var saveState: SaveState = .idle

    var hasRequiredFields: Bool {
        currentCredentials.trimmed().isComplete
    }

    var softValidationMessage: String? {
        guard !currentCredentials.trimmed().isEmpty else {
            return nil
        }
        guard hasRequiredFields else {
            return "Key ID, Issuer ID, and Private Key are required."
        }
        return nil
    }

    private let credentialsStore: CredentialsStore
    private let apiClient: any AppStoreConnectAPI

    private var hasLoaded = false
    private var isLoadingInitialData = false

    init(
        credentialsStore: CredentialsStore,
        apiClient: any AppStoreConnectAPI
    ) {
        self.credentialsStore = credentialsStore
        self.apiClient = apiClient
    }

    convenience init() {
        self.init(
            credentialsStore: KeychainCredentialsStore(),
            apiClient: AppStoreConnectClient()
        )
    }

    func load() {
        guard !hasLoaded else { return }

        hasLoaded = true
        isLoadingInitialData = true

        if let saved = credentialsStore.loadCredentials() {
            keyID = saved.keyID
            issuerID = saved.issuerID
            privateKeyPEM = saved.privateKeyPEM
        }

        isLoadingInitialData = false
    }

    func autoSave() {
        guard hasLoaded, !isLoadingInitialData else { return }
        persistCurrentCredentials()
    }

    func clearCredentials() {
        keyID = ""
        issuerID = ""
        privateKeyPEM = ""

        credentialsStore.deleteCredentials()
        saveState = .cleared
        connectionMessage = nil
        connectionSucceeded = false

        NotificationCenter.default.post(name: .appStoreConnectCredentialsDidChange, object: nil)
    }

    func testConnection() async {
        connectionMessage = nil
        connectionSucceeded = false

        let trimmed = currentCredentials.trimmed()
        guard trimmed.isComplete else {
            connectionMessage = AppStoreConnectClientError.missingCredentials.localizedDescription
            return
        }

        isTestingConnection = true
        defer { isTestingConnection = false }

        do {
            try await apiClient.testConnection(credentials: trimmed)
            connectionSucceeded = true
            connectionMessage = "Connection successful."
        } catch {
            connectionSucceeded = false
            connectionMessage = sanitizedErrorMessage(error)
        }
    }

    var currentCredentials: AppStoreConnectCredentials {
        AppStoreConnectCredentials(
            keyID: keyID,
            issuerID: issuerID,
            privateKeyPEM: privateKeyPEM
        )
    }

    private func persistCurrentCredentials() {
        let trimmed = currentCredentials.trimmed()

        if trimmed.isEmpty {
            credentialsStore.deleteCredentials()
            saveState = .cleared
            NotificationCenter.default.post(name: .appStoreConnectCredentialsDidChange, object: nil)
            return
        }

        do {
            try credentialsStore.saveCredentials(trimmed)
            saveState = .saved
            NotificationCenter.default.post(name: .appStoreConnectCredentialsDidChange, object: nil)
        } catch {
            saveState = .failed("Failed to save credentials.")
        }
    }

    private func sanitizedErrorMessage(_ error: Error) -> String {
        if let known = error as? AppStoreConnectClientError {
            return known.localizedDescription
        }

        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }

        return "Unable to validate credentials right now."
    }
}
