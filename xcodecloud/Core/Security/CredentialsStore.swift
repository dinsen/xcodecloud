import Foundation

protocol CredentialsStore {
    func loadCredentials() -> AppStoreConnectCredentials?
    func saveCredentials(_ credentials: AppStoreConnectCredentials) throws
    func deleteCredentials()
}

extension Notification.Name {
    static let appStoreConnectCredentialsDidChange = Notification.Name("appStoreConnectCredentialsDidChange")
}
