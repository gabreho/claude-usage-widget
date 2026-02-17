import Foundation

struct DateParsing {
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

    static func parseExpiryDate(_ rawValue: Any) -> Date? {
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

    static func parseTimeInterval(_ rawValue: Any) -> TimeInterval? {
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

    private static func dateFromUnixTimestamp(_ timestamp: TimeInterval) -> Date {
        // Accept both seconds and milliseconds.
        if timestamp > 10_000_000_000 {
            return Date(timeIntervalSince1970: timestamp / 1000)
        }
        return Date(timeIntervalSince1970: timestamp)
    }
}
