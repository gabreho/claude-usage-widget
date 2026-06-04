import Foundation

/// A usage source the app can display. Today: Anthropic Claude and OpenAI Codex.
///
/// Both providers expose an OAuth-protected usage endpoint that returns a "session" and a "weekly"
/// utilization window, so they share the `UsageResponse` model and the dashboard UI. Everything that
/// differs between them (endpoints, OAuth client, Keychain location) lives in ``ProviderConfig``.
public enum UsageProvider: String, CaseIterable, Sendable, Codable {
    case claude
    case codex

    /// Human-readable name shown as the section title in the dashboard.
    public var displayName: String {
        switch self {
        case .claude: return "Claude"
        case .codex: return "Codex"
        }
    }

    /// Single-character prefix used in the compact menu-bar label (e.g. `C:` / `X:`).
    public var menuBarPrefix: String {
        switch self {
        case .claude: return "C"
        case .codex: return "X"
        }
    }

    /// Label for the per-provider sign-in button.
    public var signInLabel: String {
        switch self {
        case .claude: return "Sign In with Claude"
        case .codex: return "Sign In with Codex"
        }
    }

    /// SF Symbol used next to the sign-in button.
    public var signInIcon: String {
        "person.badge.key"
    }

    var config: ProviderConfig {
        switch self {
        case .claude:
            return .claude
        case .codex:
            return .codex
        }
    }
}

/// Everything that differs between providers when talking to their OAuth + usage endpoints.
///
/// - Note: The Codex values mirror the public OpenAI Codex CLI client. The exact authorize
///   parameters, token response fields, the `wham/usage` JSON schema, and whether the usage call
///   needs an account header are confirmed by the integration spike described in the plan; the
///   constants below are the starting point and the single place to adjust once verified.
struct ProviderConfig {
    let provider: UsageProvider

    // Usage endpoint
    let usageURL: URL
    /// Static headers required by the usage endpoint (e.g. Anthropic's `anthropic-beta`).
    let usageHeaders: [String: String]

    // OAuth (PKCE)
    let authorizeURL: URL
    let tokenURL: URL
    let clientID: String
    let scopes: [String]
    let redirectURI: String
    /// Extra query items appended to the authorize request (provider-specific flags). Both providers
    /// use the standard `response_type=code` PKCE flow; only these extras differ.
    let extraAuthorizeQueryItems: [URLQueryItem]

    // Storage
    /// Keychain account the credentials JSON is stored under.
    let keychainAccount: String
    /// Top-level key inside the stored credentials JSON object.
    let credentialsRootKey: String

    var redirectURL: URL {
        URL(string: redirectURI)!
    }

    static let claude = ProviderConfig(
        provider: .claude,
        usageURL: URL(string: "https://api.anthropic.com/api/oauth/usage")!,
        usageHeaders: ["anthropic-beta": "oauth-2025-04-20"],
        authorizeURL: URL(string: "https://claude.ai/oauth/authorize")!,
        tokenURL: URL(string: "https://platform.claude.com/v1/oauth/token")!,
        // Claude Code's public OAuth client ID (PKCE, no secret). Third-party tools reuse this
        // since Anthropic doesn't offer a client registration mechanism.
        clientID: "9d1c250a-e61b-44d9-88ed-5944d1962f5e",
        // The usage endpoint (/api/oauth/usage) only requires user:profile.
        scopes: ["user:profile"],
        redirectURI: "https://platform.claude.com/oauth/code/callback",
        extraAuthorizeQueryItems: [URLQueryItem(name: "code", value: "true")],
        keychainAccount: "claude-usage-in-app-oauth",
        credentialsRootKey: "claudeAiOauth"
    )

    static let codex = ProviderConfig(
        provider: .codex,
        usageURL: URL(string: "https://chatgpt.com/backend-api/wham/usage")!,
        usageHeaders: [:],
        authorizeURL: URL(string: "https://auth.openai.com/oauth/authorize")!,
        tokenURL: URL(string: "https://auth.openai.com/oauth/token")!,
        // OpenAI Codex CLI's public OAuth client ID (PKCE, no secret).
        clientID: "app_EMoamEEZ73f0CkXaXp7hrann",
        scopes: ["openid", "profile", "email", "offline_access"],
        // Loopback redirect. The app never binds a localhost server: the embedded web view
        // intercepts the redirect navigation and reads the `code`/`state` from the query string,
        // exactly like the Claude hosted-callback interception. This is why it also works on iOS.
        redirectURI: "http://localhost:1455/auth/callback",
        extraAuthorizeQueryItems: [
            URLQueryItem(name: "id_token_add_organizations", value: "true"),
            URLQueryItem(name: "codex_cli_simplified_flow", value: "true"),
            URLQueryItem(name: "originator", value: "codex_cli_rs")
        ],
        keychainAccount: "claude-usage-codex-oauth",
        credentialsRootKey: "codexOauth"
    )
}
