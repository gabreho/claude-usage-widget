import Foundation

struct UsageResponse: Codable {
    let fiveHour: UsageLimit
    let sevenDay: UsageLimit
    let sevenDayOpus: UsageLimit?
    let sevenDaySonnet: UsageLimit?
    let extraUsage: ExtraUsage?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
        case extraUsage = "extra_usage"
    }
}

struct UsageLimit: Codable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    var resetDate: Date? {
        guard let resetsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: resetsAt) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: resetsAt)
    }

    var tier: UsageTier {
        switch utilization {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }
}

struct ExtraUsage: Codable {}

enum UsageTier {
    case green, yellow, red
}
