import Foundation

struct OAuthTokenClient {
    private static let oauthTokenURL = URL(string: "https://platform.claude.com/v1/oauth/token")!

    // TODO: (claude-usage-4vj) This is Claude Code's client ID — not a dedicated client for this app.
    // We should investigate registering our own OAuth client and narrowing scopes to only what
    // /api/oauth/usage requires. Currently both authorize and refresh request the full Claude Code
    // scope set, which is far more privilege than a usage-only widget needs.
    private static let oauthClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private static let oauthRefreshScopes = [
        "user:profile",
        "user:inference",
        "user:sessions:claude_code",
        "user:mcp_servers"
    ]

    struct RefreshedTokens {
        let accessToken: String
        let refreshToken: String
        let expiresAt: Date
        let expiresAtStorageValue: Any
    }

    static func exchangeAuthorizationCode(
        code: String,
        state: String,
        codeVerifier: String
    ) async throws -> RefreshedTokens {
        let requestBody: [String: Any] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": UsageService.oauthRedirectURI,
            "client_id": oauthClientID,
            "code_verifier": codeVerifier,
            "state": state
        ]

        return try await performTokenRequest(body: requestBody, timeout: 20)
    }

    static func refreshTokens(using refreshToken: String) async throws -> RefreshedTokens {
        let requestBody: [String: Any] = [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": oauthClientID,
            "scope": oauthRefreshScopes.joined(separator: " ")
        ]

        return try await performTokenRequest(body: requestBody, timeout: 15)
    }

    private static func performTokenRequest(
        body: [String: Any],
        timeout: TimeInterval
    ) async throws -> RefreshedTokens {
        let bodyData: Data
        do {
            bodyData = try JSONSerialization.data(withJSONObject: body)
        } catch {
            throw UsageServiceError.decodingError(error)
        }

        var request = URLRequest(url: oauthTokenURL)
        request.httpMethod = "POST"
        request.httpBody = bodyData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = timeout

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw UsageServiceError.networkError(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw UsageServiceError.networkError(
                NSError(domain: "OAuthTokenClient", code: -1)
            )
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            let message = parseErrorMessage(from: data)
            throw UsageServiceError.httpError(statusCode: httpResponse.statusCode, message: message)
        }

        return try parseOAuthTokens(from: data)
    }

    static func parseErrorMessage(from data: Data) -> String? {
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

    private static func parseOAuthTokens(from data: Data) throws -> RefreshedTokens {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw UsageServiceError.decodingError(
                NSError(domain: "OAuthTokenClient", code: -2, userInfo: [NSLocalizedDescriptionKey: "OAuth token response was not a JSON object"])
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
            guard let expiresAt = DateParsing.parseExpiryDate(rawExpiresAt) else {
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
           let expiresIn = DateParsing.parseTimeInterval(rawExpiresIn) {
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
}
