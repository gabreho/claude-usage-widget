import Foundation
import Security

public enum UsageServiceError: LocalizedError {
    case keychainNotFound
    case keychainAccountMissing
    case tokenMissing
    case refreshTokenMissing
    case tokenExpiryMissing
    case tokenExpiryInvalid
    case keychainWriteFailed(status: OSStatus)
    case networkError(Error)
    case httpError(statusCode: Int, message: String?)
    case decodingError(Error)

    public var errorDescription: String? {
        switch self {
        case .keychainNotFound:
            return "Claude Code credentials not found in Keychain"
        case .keychainAccountMissing:
            return "Keychain credential is missing account metadata"
        case .tokenMissing:
            return "OAuth access token missing from credentials"
        case .refreshTokenMissing:
            return "OAuth refresh token missing from credentials"
        case .tokenExpiryMissing:
            return "OAuth token expiry missing from credentials"
        case .tokenExpiryInvalid:
            return "OAuth token expiry is invalid"
        case .keychainWriteFailed(let status):
            return "Failed to update OAuth credentials in Keychain (OSStatus \(status))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            switch statusCode {
            case 401:
                return "Token expired — run `claude auth login` to refresh"
            case 403:
                return message ?? "Access denied (HTTP 403)"
            default:
                return message ?? "API returned HTTP \(statusCode)"
            }
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }
}

public struct UsageService {
    private static let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthTokenURL = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    private static let keychainService = "Claude Code-credentials"
    private static let refreshSkewSeconds: TimeInterval = 300
    private static let iso8601WithFractionalSecondsFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    private struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let expiresAtStorageValue: Any
    }

    private static func readKeychainData() throws -> (data: Data, account: String) {
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

    private static func parseExpiryDate(_ rawValue: Any) -> Date? {
        if let seconds = rawValue as? TimeInterval {
            return dateFromUnixTimestamp(seconds)
        }

        if let seconds = rawValue as? Int {
            return dateFromUnixTimestamp(TimeInterval(seconds))
        }

        if let stringValue = rawValue as? String {
            if let seconds = TimeInterval(stringValue) {
                return dateFromUnixTimestamp(seconds)
            }

            if let date = iso8601WithFractionalSecondsFormatter.date(from: stringValue) {
                return date
            }

            return iso8601Formatter.date(from: stringValue)
        }

        return nil
    }

    private static func dateFromUnixTimestamp(_ timestamp: TimeInterval) -> Date {
        // Accept both seconds and milliseconds.
        if timestamp > 10_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1000)
        }
        return Date(timeIntervalSince1970: timestamp)
    }

    private static func readStoredCredentials() throws -> (rootJSON: [String: Any], credentials: OAuthCredentials, account: String) {
        let (data, account) = try readKeychainData()

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json["claudeAiOauth"] as? [String: Any] else {
            throw UsageServiceError.tokenMissing
        }

        guard let accessToken = oauthDict["accessToken"] as? String else {
            throw UsageServiceError.tokenMissing
        }

        guard let refreshToken = oauthDict["refreshToken"] as? String else {
            throw UsageServiceError.refreshTokenMissing
        }

        guard let rawExpiresAt = oauthDict["expiresAt"] else {
            throw UsageServiceError.tokenExpiryMissing
        }

        guard let expiresAt = parseExpiryDate(rawExpiresAt) else {
            throw UsageServiceError.tokenExpiryInvalid
        }

        return (
            json,
            OAuthCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            ),
            account
        )
    }

    private static func parseErrorMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        if let error = json["error"] as? String {
            if let errorDescription = json["error_description"] as? String {
                return "\(error): \(errorDescription)"
            }
            return error
        }

        if let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }

        if let errorDescription = json["error_description"] as? String {
            return errorDescription
        }

        if let message = json["message"] as? String {
            return message
        }

        return nil
    }

    private static func shouldRefreshToken(expiringAt expiresAt: Date) -> Bool {
        expiresAt.timeIntervalSinceNow <= refreshSkewSeconds
    }

    private static func parseTimeInterval(_ rawValue: Any) -> TimeInterval? {
        if let seconds = rawValue as? TimeInterval {
            return seconds
        }

        if let seconds = rawValue as? Int {
            return TimeInterval(seconds)
        }

        if let seconds = rawValue as? String {
            return TimeInterval(seconds)
        }

        return nil
    }

    private static func parseRefreshedTokens(from data: Data) throws -> RefreshedTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageServiceError.decodingError(
                NSError(domain: "UsageService", code: -2, userInfo: [NSLocalizedDescriptionKey: "OAuth token response was not a JSON object"])
            )
        }

        let accessToken = (json["access_token"] as? String) ?? (json["accessToken"] as? String)
        guard let accessToken, !accessToken.isEmpty else {
            throw UsageServiceError.tokenMissing
        }

        let refreshToken = (json["refresh_token"] as? String) ?? (json["refreshToken"] as? String)
        guard let refreshToken, !refreshToken.isEmpty else {
            throw UsageServiceError.refreshTokenMissing
        }

        if let rawExpiresAt = json["expires_at"] ?? json["expiresAt"] {
            guard let expiresAt = parseExpiryDate(rawExpiresAt) else {
                throw UsageServiceError.tokenExpiryInvalid
            }

            return RefreshedTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                expiresAtStorageValue: rawExpiresAt
            )
        }

        if let rawExpiresIn = json["expires_in"] ?? json["expiresIn"],
           let expiresIn = parseTimeInterval(rawExpiresIn) {
            let expiresAt = Date().addingTimeInterval(expiresIn)
            return RefreshedTokens(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt,
                expiresAtStorageValue: Int(expiresAt.timeIntervalSince1970)
            )
        }

        throw UsageServiceError.tokenExpiryMissing
    }

    private static func refreshTokens(using refreshToken: String) async throws -> RefreshedTokens {
        var bodyComponents = URLComponents()
        bodyComponents.queryItems = [
            URLQueryItem(name: "grant_type", value: "refresh_token"),
            URLQueryItem(name: "refresh_token", value: refreshToken)
        ]
        let body = bodyComponents.percentEncodedQuery ?? ""
        var request = URLRequest(url: oauthTokenURL)
        request.httpMethod = "POST"
        request.httpBody = body.data(using: .utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.networkError(
                NSError(domain: "UsageService", code: -1)
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data)
            throw UsageServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try parseRefreshedTokens(from: data)
    }

    private static func writeUpdatedCredentials(
        _ rootJSON: [String: Any],
        account: String
    ) throws {
        let data = try JSONSerialization.data(withJSONObject: rootJSON)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account
        ]

        let attributesToUpdate: [String: Any] = [
            kSecValueData as String: data
        ]

        let status = SecItemUpdate(query as CFDictionary, attributesToUpdate as CFDictionary)
        guard status == errSecSuccess else {
            throw UsageServiceError.keychainWriteFailed(status: status)
        }
    }

    private static func refreshCredentialsIfNeeded(
        rootJSON: [String: Any],
        credentials: OAuthCredentials,
        account: String
    ) async throws -> OAuthCredentials {
        guard shouldRefreshToken(expiringAt: credentials.expiresAt) else {
            return credentials
        }

        let refreshed = try await refreshTokens(using: credentials.refreshToken)

        var updatedRootJSON = rootJSON
        var oauthJSON = (updatedRootJSON["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauthJSON["accessToken"] = refreshed.accessToken
        oauthJSON["refreshToken"] = refreshed.refreshToken
        oauthJSON["expiresAt"] = refreshed.expiresAtStorageValue
        updatedRootJSON["claudeAiOauth"] = oauthJSON

        try writeUpdatedCredentials(updatedRootJSON, account: account)

        return OAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt
        )
    }

    public static func fetchUsage() async throws -> UsageResponse {
        let stored = try readStoredCredentials()
        let credentials = try await refreshCredentialsIfNeeded(
            rootJSON: stored.rootJSON,
            credentials: stored.credentials,
            account: stored.account
        )

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.networkError(
                NSError(domain: "UsageService", code: -1)
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = Self.parseErrorMessage(from: data)
            throw UsageServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }
}
