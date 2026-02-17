import Foundation

public enum UsageServiceError: LocalizedError {
    case keychainNotFound
    case keychainAccountMissing
    case tokenMissing
    case refreshTokenMissing
    case tokenExpiryMissing
    case tokenExpiryInvalid
    case oauthCodeMissing
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
        case .oauthCodeMissing:
            return "OAuth authorization code missing from callback"
        case .keychainWriteFailed(let status):
            return "Failed to update OAuth credentials in Keychain (OSStatus \(status))"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .httpError(let statusCode, let message):
            switch statusCode {
            case 401:
                return "Token expired — sign in again (or run `claude auth login`)"
            case 403:
                return message ?? "Access denied (HTTP 403)"
            default:
                return message ?? "API returned HTTP \(statusCode)"
            }
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        }
    }

    public var supportsInAppLoginRecovery: Bool {
        switch self {
        case .keychainNotFound,
             .keychainAccountMissing,
             .tokenMissing,
             .refreshTokenMissing,
             .tokenExpiryMissing,
             .tokenExpiryInvalid,
             .oauthCodeMissing:
            return true
        case .httpError(let statusCode, _):
            return statusCode == 401
        default:
            return false
        }
    }
}

public struct UsageService {
    private static let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let oauthAuthorizeURL = URL(string: "https://claude.ai/oauth/authorize")!
    // Claude Code's public OAuth client ID (PKCE, no secret). Third-party tools reuse this
    // since Anthropic doesn't offer a client registration mechanism.
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    // The usage endpoint (/api/oauth/usage) only requires user:profile.
    private static let oauthAuthorizeScopes = ["user:profile"]
    public static let oauthRedirectURI = "https://platform.claude.com/oauth/code/callback"
    private static let refreshSkewSeconds: TimeInterval = 300

    struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    public struct OAuthAuthorizationSession {
        public let authorizationURL: URL
        public let state: String
        public let codeVerifier: String

        public init(authorizationURL: URL, state: String, codeVerifier: String) {
            self.authorizationURL = authorizationURL
            self.state = state
            self.codeVerifier = codeVerifier
        }
    }

    public static var oauthRedirectURL: URL {
        URL(string: oauthRedirectURI)!
    }

    // MARK: - OAuth Authorization

    public static func createOAuthAuthorizationSession() -> OAuthAuthorizationSession {
        let codeVerifier = PKCEUtility.randomURLSafeString(byteCount: 32)
        let codeChallenge = PKCEUtility.codeChallenge(for: codeVerifier)
        let state = PKCEUtility.randomURLSafeString(byteCount: 24)

        var components = URLComponents(url: oauthAuthorizeURL, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "code", value: "true"),
            URLQueryItem(name: "client_id", value: oauthClientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: oauthRedirectURI),
            URLQueryItem(name: "scope", value: oauthAuthorizeScopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]

        return OAuthAuthorizationSession(
            authorizationURL: components.url!,
            state: state,
            codeVerifier: codeVerifier
        )
    }

    public static func completeOAuthAuthorization(
        code: String,
        state: String,
        codeVerifier: String
    ) async throws {
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw UsageServiceError.oauthCodeMissing
        }

        let exchanged = try await OAuthTokenClient.exchangeAuthorizationCode(
            code: trimmedCode,
            state: state,
            codeVerifier: codeVerifier
        )

        let currentCredentials = KeychainService.currentCredentialsRootJSONForWrite()
        var rootJSON = currentCredentials.rootJSON

        var oauthJSON = (rootJSON["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauthJSON["accessToken"] = exchanged.accessToken
        oauthJSON["refreshToken"] = exchanged.refreshToken
        oauthJSON["expiresAt"] = exchanged.expiresAtStorageValue
        rootJSON["claudeAiOauth"] = oauthJSON

        try KeychainService.writeUpdatedCredentials(rootJSON, account: currentCredentials.account)
    }

    // MARK: - Usage Fetching

    public static func fetchUsage() async throws -> UsageResponse {
        let stored = try readStoredCredentials()
        let credentials = try await refreshCredentialsIfNeeded(
            rootJSON: stored.rootJSON,
            credentials: stored.credentials,
            account: stored.account,
            isOwnedByApp: stored.isOwnedByApp
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
            let message = OAuthTokenClient.parseErrorMessage(from: data)
            throw UsageServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }

    // MARK: - Credential Management

    private static func readStoredCredentials() throws -> (rootJSON: [String: Any], credentials: OAuthCredentials, account: String, isOwnedByApp: Bool) {
        // Prefer in-app OAuth credentials; fall back to Claude Code's entry (read-only).
        let data: Data
        let account: String
        let isOwnedByApp: Bool
        if let inApp = KeychainService.readKeychainData(forAccount: KeychainService.inAppOAuthAccount) {
            (data, account) = inApp
            isOwnedByApp = true
        } else {
            (data, account) = try KeychainService.readKeychainData()
            isOwnedByApp = false
        }

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

        guard let expiresAt = DateParsing.parseExpiryDate(rawExpiresAt) else {
            throw UsageServiceError.tokenExpiryInvalid
        }

        return (
            json,
            OAuthCredentials(
                accessToken: accessToken,
                refreshToken: refreshToken,
                expiresAt: expiresAt
            ),
            account,
            isOwnedByApp
        )
    }

    private static func refreshCredentialsIfNeeded(
        rootJSON: [String: Any],
        credentials: OAuthCredentials,
        account: String,
        isOwnedByApp: Bool
    ) async throws -> OAuthCredentials {
        guard credentials.expiresAt.timeIntervalSinceNow <= refreshSkewSeconds else {
            return credentials
        }

        // Never refresh tokens we don't own — rotating Claude Code's refresh token
        // would invalidate their session. Use the access token as-is; if it's expired
        // the API will return 401 and the user can do an in-app login.
        guard isOwnedByApp else {
            return credentials
        }

        let refreshed = try await OAuthTokenClient.refreshTokens(using: credentials.refreshToken)

        var updatedRootJSON = rootJSON
        var oauthJSON = (updatedRootJSON["claudeAiOauth"] as? [String: Any]) ?? [:]
        oauthJSON["accessToken"] = refreshed.accessToken
        oauthJSON["refreshToken"] = refreshed.refreshToken
        oauthJSON["expiresAt"] = refreshed.expiresAtStorageValue
        updatedRootJSON["claudeAiOauth"] = oauthJSON

        try KeychainService.writeUpdatedCredentials(updatedRootJSON, account: account)

        return OAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt
        )
    }
}
