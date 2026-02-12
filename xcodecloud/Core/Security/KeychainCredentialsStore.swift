import Foundation
import Security

struct KeychainCredentialsStore: CredentialsStore {
    private enum Constants {
        static let serviceName = "ios.dinsen.xcodecloud"
        static let accountName = "appStoreConnectCredentials"
    }

    func loadCredentials() -> AppStoreConnectCredentials? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.serviceName,
            kSecAttrAccount as String: Constants.accountName,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }

        return try? JSONDecoder().decode(AppStoreConnectCredentials.self, from: data)
    }

    func saveCredentials(_ credentials: AppStoreConnectCredentials) throws {
        let data = try JSONEncoder().encode(credentials)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.serviceName,
            kSecAttrAccount as String: Constants.accountName,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainCredentialsStoreError.saveFailed(status)
        }
    }

    func deleteCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Constants.serviceName,
            kSecAttrAccount as String: Constants.accountName,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainCredentialsStoreError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            "Unable to save credentials to Keychain (status: \(status))."
        }
    }
}
