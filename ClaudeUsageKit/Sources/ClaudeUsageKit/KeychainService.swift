import Foundation
import Security

struct KeychainService {
    static let keychainService = "Claude Code-credentials"
    static let inAppOAuthAccount = "claude-usage-in-app-oauth"

    static func readKeychainData(forAccount account: String) -> (data: Data, account: String)? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data else {
            return nil
        }
        return (data, account)
    }

    static func readKeychainData() throws -> (data: Data, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let item = result as? [String: Any],
              let data = item[kSecValueData as String] as? Data else {
            throw UsageServiceError.keychainNotFound
        }

        guard let account = item[kSecAttrAccount as String] as? String, !account.isEmpty else {
            throw UsageServiceError.keychainAccountMissing
        }
        return (data, account)
    }

    static func writeCredentialsData(
        _ data: Data,
        account: String
    ) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
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

    static func currentCredentialsRootJSONForWrite() -> (rootJSON: [String: Any], account: String) {
        // Always target the in-app account to avoid overwriting Claude Code's credentials.
        guard let existing = readKeychainData(forAccount: inAppOAuthAccount) else {
            return ([:], inAppOAuthAccount)
        }
        let rootJSON = (try? JSONSerialization.jsonObject(with: existing.data) as? [String: Any]) ?? [:]
        return (rootJSON, inAppOAuthAccount)
    }
}
