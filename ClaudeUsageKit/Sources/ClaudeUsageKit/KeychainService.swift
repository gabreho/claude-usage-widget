import Foundation
import Security

struct KeychainService {
    static let keychainService = "claude-usage-credentials"
    static let inAppOAuthAccount = "claude-usage-in-app-oauth"

    // Use the data protection keychain (macOS 10.15+) to avoid ACL-based access prompts.
    // Items are scoped to the app's implicit access group (TeamID.BundleID) with no user dialogs.
    private static let dataProtectionKeychain: Bool = true

    static func readInAppCredentials() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: inAppOAuthAccount,
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data else {
            return nil
        }
        return data
    }

    static func writeCredentialsData(
        _ data: Data,
        account: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var itemToAdd = query
            itemToAdd[kSecValueData as String] = data
            let addStatus = SecItemAdd(itemToAdd as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw UsageServiceError.keychainWriteFailed(status: addStatus)
            }
        default:
            throw UsageServiceError.keychainWriteFailed(status: status)
        }
    }

    static func writeUpdatedCredentials(
        _ rootJSON: [String: Any],
        account: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: rootJSON)
        try writeCredentialsData(data, account: account)
    }

    static func deleteInAppCredentials() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: inAppOAuthAccount,
            kSecUseDataProtectionKeychain as String: dataProtectionKeychain
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func currentCredentialsRootJSONForWrite() -> [String: Any] {
        guard let data = readInAppCredentials() else {
            return [:]
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
}
