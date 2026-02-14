import Foundation
import Security

enum UsageServiceError: LocalizedError {
    case keychainNotFound
    case tokenMissing
    case networkError(Error)
    case httpError(statusCode: Int)
    case decodingError(Error)

    var errorDescription: String? {
        switch self {
        case .keychainNotFound:
            return "Claude Code credentials not found in Keychain"
        case .tokenMissing:
            return "OAuth access token missing from credentials"
        case .networkError(let e):
            return "Network error: \(e.localizedDescription)"
        case .httpError(let code):
            if code == 401 {
                return "Token expired — open Claude Code to refresh"
            }
            return "API returned HTTP \(code)"
        case .decodingError(let e):
            return "Failed to decode response: \(e.localizedDescription)"
        }
    }
}

struct UsageService {
    private static let apiURL = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    private static let keychainService = "Claude Code-credentials"

    static func readAccessToken() throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else {
            throw UsageServiceError.keychainNotFound
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauthDict = json["claudeAiOauth"] as? [String: Any],
              let token = oauthDict["accessToken"] as? String else {
            throw UsageServiceError.tokenMissing
        }

        return token
    }

    static func fetchUsage() async throws -> UsageResponse {
        let token = try readAccessToken()

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response): (Data, URLResponse)
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
            throw UsageServiceError.httpError(statusCode: httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageResponse.self, from: data)
        } catch {
            throw UsageServiceError.decodingError(error)
        }
    }
}
