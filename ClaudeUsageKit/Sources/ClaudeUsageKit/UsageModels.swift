import Foundation

public struct UsageResponse: Codable, Sendable {
    public let fiveHour: UsageLimit
    public let sevenDay: UsageLimit
    public let sevenDayOpus: UsageLimit?
    public let sevenDaySonnet: UsageLimit?
    public let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

public struct UsageLimit: Codable, Sendable {
    public let utilization: Double
    public let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    public var resetDate: Date? {
        guard let resetsAt else { return nil }
        if let date = Self.iso8601WithFractionalSeconds.date(from: resetsAt) {
            return date
        }
        return Self.iso8601WithoutFractionalSeconds.date(from: resetsAt)
    }

    public var tier: UsageTier {
        switch utilization {
        case ..<50:
            return .green
        case ..<80:
            return .yellow
        default:
            return .red
        }
    }

    private static let iso8601WithFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601WithoutFractionalSeconds: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

public struct ExtraUsage: Codable, Sendable {
    /// Whether extra usage is enabled for the account.
    public let isEnabled: Bool?
    /// Current monthly extra usage cap in credits.
    public let monthlyLimit: Double?
    /// Credits consumed from the monthly extra usage cap.
    public let usedCredits: Double?
    /// Percent of monthly extra usage consumed.
    public let utilization: Double?

    // Legacy fields retained for backward compatibility with previously stored snapshots.
    private let spend: Double?
    private let limit: Double?
    private let balance: Double?

    enum CodingKeys: String, CodingKey {
        case isEnabled = "is_enabled"
        case monthlyLimit = "monthly_limit"
        case usedCredits = "used_credits"
        case utilization
        case spend
        case limit
        case balance
    }

    public var effectiveUsedCredits: Double? {
        usedCredits ?? spend
    }

    public var effectiveMonthlyLimit: Double? {
        monthlyLimit ?? limit
    }

    public var effectiveUtilization: Double? {
        if let utilization {
            return utilization
        }
        if let used = effectiveUsedCredits,
           let monthlyLimit = effectiveMonthlyLimit,
           monthlyLimit > 0 {
            return (used / monthlyLimit) * 100
        }
        return nil
    }

    public var remainingCredits: Double? {
        if let monthlyLimit = effectiveMonthlyLimit,
           let used = effectiveUsedCredits {
            return max(monthlyLimit - used, 0)
        }
        return balance
    }

    public var hasData: Bool {
        guard isEnabled != false else { return false }
        return effectiveUsedCredits != nil
            || effectiveMonthlyLimit != nil
            || effectiveUtilization != nil
            || remainingCredits != nil
    }
}

public enum UsageTier: Sendable {
    case green
    case yellow
    case red
}
