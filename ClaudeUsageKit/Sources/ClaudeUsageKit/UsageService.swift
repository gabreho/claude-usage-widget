import Foundation

public enum UsageServiceError: LocalizedError {
    case keychainNotFound
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
            return "Sign in to view your usage"
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
                return "Session expired — sign in again"
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
    private static let refreshSkewSeconds: TimeInterval = 300

    struct OAuthCredentials {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
    }

    public struct OAuthAuthorizationSession {
        public let provider: UsageProvider
        public let authorizationURL: URL
        public let state: String
        public let codeVerifier: String

        public init(provider: UsageProvider, authorizationURL: URL, state: String, codeVerifier: String) {
            self.provider = provider
            self.authorizationURL = authorizationURL
            self.state = state
            self.codeVerifier = codeVerifier
        }
    }

    /// Redirect URL the embedded web view watches for, for the given provider.
    public static func oauthRedirectURL(for provider: UsageProvider = .claude) -> URL {
        provider.config.redirectURL
    }

    // MARK: - Sign Out

    public static func isAuthenticated(provider: UsageProvider = .claude) -> Bool {
        KeychainService.readInAppCredentials(account: provider.config.keychainAccount) != nil
    }

    public static func signOut(provider: UsageProvider = .claude) {
        KeychainService.deleteInAppCredentials(account: provider.config.keychainAccount)
    }

    // MARK: - OAuth Authorization

    public static func createOAuthAuthorizationSession(provider: UsageProvider = .claude) -> OAuthAuthorizationSession {
        let config = provider.config
        let codeVerifier = PKCEUtility.randomURLSafeString(byteCount: 32)
        let codeChallenge = PKCEUtility.codeChallenge(for: codeVerifier)
        let state = PKCEUtility.randomURLSafeString(byteCount: 24)

        var components = URLComponents(url: config.authorizeURL, resolvingAgainstBaseURL: false)!
        var queryItems = [
            URLQueryItem(name: "client_id", value: config.clientID),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: config.redirectURI),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        queryItems.append(contentsOf: config.extraAuthorizeQueryItems)
        components.queryItems = queryItems

        return OAuthAuthorizationSession(
            provider: provider,
            authorizationURL: components.url!,
            state: state,
            codeVerifier: codeVerifier
        )
    }

    public static func completeOAuthAuthorization(
        provider: UsageProvider = .claude,
        code: String,
        state: String,
        codeVerifier: String
    ) async throws {
        let config = provider.config
        let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCode.isEmpty else {
            throw UsageServiceError.oauthCodeMissing
        }

        let exchanged = try await OAuthTokenClient.exchangeAuthorizationCode(
            config: config,
            code: trimmedCode,
            state: state,
            codeVerifier: codeVerifier
        )

        var rootJSON = KeychainService.currentCredentialsRootJSONForWrite(account: config.keychainAccount)

        var oauthJSON = (rootJSON[config.credentialsRootKey] as? [String: Any]) ?? [:]
        oauthJSON["accessToken"] = exchanged.accessToken
        oauthJSON["refreshToken"] = exchanged.refreshToken
        oauthJSON["expiresAt"] = exchanged.expiresAtStorageValue
        rootJSON[config.credentialsRootKey] = oauthJSON

        try KeychainService.writeUpdatedCredentials(rootJSON, account: config.keychainAccount)
    }

    // MARK: - Usage Fetching

    public static func fetchUsage(provider: UsageProvider = .claude) async throws -> UsageResponse {
        let config = provider.config
        let stored = try readStoredCredentials(config: config)
        let credentials = try await refreshCredentialsIfNeeded(
            config: config,
            rootJSON: stored.rootJSON,
            credentials: stored.credentials
        )

        var request = URLRequest(url: config.usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        for (field, value) in config.usageHeaders {
            request.setValue(value, forHTTPHeaderField: field)
        }
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

        return try decodeUsage(provider: provider, data: data)
    }

    private static func decodeUsage(provider: UsageProvider, data: Data) throws -> UsageResponse {
        do {
            switch provider {
            case .claude:
                return try JSONDecoder().decode(UsageResponse.self, from: data)
            case .codex:
                return try JSONDecoder().decode(CodexUsageResponse.self, from: data).toUsageResponse()
            }
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }

    // MARK: - Credential Management

    private static func readStoredCredentials(config: ProviderConfig) throws -> (rootJSON: [String: Any], credentials: OAuthCredentials) {
        guard let data = KeychainService.readInAppCredentials(account: config.keychainAccount) else {
            throw UsageServiceError.keychainNotFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json[config.credentialsRootKey] as? [String: Any] else {
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
            )
        )
    }

    private static func refreshCredentialsIfNeeded(
        config: ProviderConfig,
        rootJSON: [String: Any],
        credentials: OAuthCredentials
    ) async throws -> OAuthCredentials {
        guard credentials.expiresAt.timeIntervalSinceNow <= refreshSkewSeconds else {
            return credentials
        }

        let refreshed = try await OAuthTokenClient.refreshTokens(config: config, using: credentials.refreshToken)

        var updatedRootJSON = rootJSON
        var oauthJSON = (updatedRootJSON[config.credentialsRootKey] as? [String: Any]) ?? [:]
        oauthJSON["accessToken"] = refreshed.accessToken
        oauthJSON["refreshToken"] = refreshed.refreshToken
        oauthJSON["expiresAt"] = refreshed.expiresAtStorageValue
        updatedRootJSON[config.credentialsRootKey] = oauthJSON

        try KeychainService.writeUpdatedCredentials(updatedRootJSON, account: config.keychainAccount)

        return OAuthCredentials(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt
        )
    }
}
