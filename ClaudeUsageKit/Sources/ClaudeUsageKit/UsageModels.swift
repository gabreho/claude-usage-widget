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
    /// Current month's extra spend in USD (charged when rate limits are exceeded).
    public let spend: Double?
    /// User-configured monthly extra spend limit in USD.
    public let limit: Double?
    /// Remaining balance in USD (limit − spend).
    public let balance: Double?

    enum CodingKeys: String, CodingKey {
        case spend
        case limit
        case balance
    }

    public var hasData: Bool { spend != nil }
}

public enum UsageTier: Sendable {
    case green
    case yellow
    case red
}
