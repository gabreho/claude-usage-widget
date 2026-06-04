import Foundation

/// Decoded shape of the OpenAI Codex `GET https://chatgpt.com/backend-api/wham/usage` response.
///
/// Codex reports a `primary_window` (session lane) and a `secondary_window` (weekly lane), each as a
/// used-percent plus a reset countdown, alongside optional `additional_rate_limits` (model-specific
/// limits such as GPT-5.x-Codex-Spark). This maps onto the shared ``UsageResponse`` so the existing
/// dashboard renders Codex without UI changes.
///
/// - Note: The field layout is intentionally lenient (windows accepted nested under `rate_limit` or at
///   the top level; reset accepted as `resets_in_seconds` or `reset_at`) because the exact schema is
///   confirmed by the integration spike. Decoding never throws on missing windows — it yields zeroed
///   lanes so a partial response still renders.
public struct CodexUsageResponse: Decodable, Sendable {
    public let primaryWindow: CodexRateWindow?
    public let secondaryWindow: CodexRateWindow?
    public let additionalRateLimits: [CodexAdditionalRateLimit]

    enum TopLevelKeys: String, CodingKey {
        case rateLimit = "rate_limit"
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
        case additionalRateLimits = "additional_rate_limits"
    }

    enum RateLimitKeys: String, CodingKey {
        case primaryWindow = "primary_window"
        case secondaryWindow = "secondary_window"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TopLevelKeys.self)

        // Windows may live under a nested `rate_limit` object or directly at the top level.
        if let nested = try? container.nestedContainer(keyedBy: RateLimitKeys.self, forKey: .rateLimit) {
            primaryWindow = try nested.decodeIfPresent(CodexRateWindow.self, forKey: .primaryWindow)
            secondaryWindow = try nested.decodeIfPresent(CodexRateWindow.self, forKey: .secondaryWindow)
        } else {
            primaryWindow = try container.decodeIfPresent(CodexRateWindow.self, forKey: .primaryWindow)
            secondaryWindow = try container.decodeIfPresent(CodexRateWindow.self, forKey: .secondaryWindow)
        }

        // `additional_rate_limits` is sometimes absent or a non-array sentinel; tolerate both.
        additionalRateLimits = (try? container.decodeIfPresent([CodexAdditionalRateLimit].self, forKey: .additionalRateLimits)) ?? []
    }
}

public struct CodexRateWindow: Decodable, Sendable {
    /// 0–100 utilization for the window.
    public let usedPercent: Double
    /// Seconds until this window resets, when provided.
    public let resetsInSeconds: TimeInterval?
    /// Absolute reset timestamp (ISO8601 or epoch seconds), when provided.
    public let resetAtRaw: String?
    /// Total length of the window in seconds (e.g. 18000 for the 5-hour session lane).
    public let limitWindowSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case usedPercent = "used_percent"
        case resetsInSeconds = "resets_in_seconds"
        case resetAt = "reset_at"
        case limitWindowSeconds = "limit_window_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        usedPercent = (try? container.decode(Double.self, forKey: .usedPercent)) ?? 0
        resetsInSeconds = try? container.decodeIfPresent(Double.self, forKey: .resetsInSeconds)
        limitWindowSeconds = try? container.decodeIfPresent(Double.self, forKey: .limitWindowSeconds)
        // `reset_at` may arrive as an ISO8601 string or an epoch number.
        if let stringValue = try? container.decodeIfPresent(String.self, forKey: .resetAt) {
            resetAtRaw = stringValue
        } else if let numberValue = try? container.decodeIfPresent(Double.self, forKey: .resetAt) {
            resetAtRaw = String(numberValue)
        } else {
            resetAtRaw = nil
        }
    }

    /// Resolves the reset instant from whichever field the API supplied.
    func resetDate(now: Date) -> Date? {
        if let resetsInSeconds {
            return now.addingTimeInterval(resetsInSeconds)
        }
        if let resetAtRaw {
            return DateParsing.parseExpiryDate(resetAtRaw)
        }
        return nil
    }
}

public struct CodexAdditionalRateLimit: Decodable, Sendable {
    public let id: String?
    public let title: String?
    public let usedPercent: Double
    public let resetsInSeconds: TimeInterval?

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case usedPercent = "used_percent"
        case resetsInSeconds = "resets_in_seconds"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try? container.decodeIfPresent(String.self, forKey: .id)
        title = try? container.decodeIfPresent(String.self, forKey: .title)
        usedPercent = (try? container.decode(Double.self, forKey: .usedPercent)) ?? 0
        resetsInSeconds = try? container.decodeIfPresent(Double.self, forKey: .resetsInSeconds)
    }
}

extension CodexUsageResponse {
    private static let iso8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    /// Projects the Codex usage shape onto the shared ``UsageResponse`` (session → 5-hour lane,
    /// weekly → 7-day lane) so the existing dashboard/metrics views render it unchanged.
    ///
    /// `additional_rate_limits` (e.g. Codex Spark) are decoded but not surfaced in v1 to avoid
    /// mislabeling them as the Claude-specific Opus/Sonnet buckets; a future pass can generalize the
    /// metric labels to show them.
    public func toUsageResponse(now: Date = Date()) -> UsageResponse {
        UsageResponse(
            fiveHour: Self.limit(from: primaryWindow, now: now),
            sevenDay: Self.limit(from: secondaryWindow, now: now),
            sevenDayOpus: nil,
            sevenDaySonnet: nil,
            extraUsage: nil
        )
    }

    private static func limit(from window: CodexRateWindow?, now: Date) -> UsageLimit {
        guard let window else {
            return UsageLimit(utilization: 0, resetsAt: nil)
        }
        let resetsAt = window.resetDate(now: now).map { iso8601.string(from: $0) }
        return UsageLimit(utilization: window.usedPercent, resetsAt: resetsAt)
    }
}
