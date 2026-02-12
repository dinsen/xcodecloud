import Foundation
import Observation

@MainActor
@Observable
final class BuildFeedStore {
    private(set) var credentials: AppStoreConnectCredentials?

    var hasCompleteCredentials: Bool {
        credentials?.isComplete ?? false
    }

    private let credentialsStore: CredentialsStore

    init(credentialsStore: CredentialsStore) {
        self.credentialsStore = credentialsStore
        self.credentials = credentialsStore.loadCredentials()

        _ = NotificationCenter.default.addObserver(
            forName: .appStoreConnectCredentialsDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.reloadCredentials()
            }
        }
    }

    convenience init() {
        self.init(credentialsStore: KeychainCredentialsStore())
    }

    func reloadCredentials() {
        credentials = credentialsStore.loadCredentials()
    }
}
