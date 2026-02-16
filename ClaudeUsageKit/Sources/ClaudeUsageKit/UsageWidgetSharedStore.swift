import Foundation

public enum UsageWidgetSharedStore {
    public static let appGroupIdentifier = "group.com.gabreho.claude-usage"
    public static let widgetKind = "ClaudeUsageWidget"

    private static let snapshotKey = "claude_usage_widget_snapshot_v1"

    public struct Snapshot: Codable, Sendable {
        public let usage: UsageResponse
        public let fetchedAt: Date

        public init(usage: UsageResponse, fetchedAt: Date) {
            self.usage = usage
            self.fetchedAt = fetchedAt
        }
    }

    public static func save(usage: UsageResponse, fetchedAt: Date = Date()) {
        save(Snapshot(usage: usage, fetchedAt: fetchedAt))
    }

    public static func save(_ snapshot: Snapshot) {
        guard let defaults = sharedDefaults() else {
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKey)
    }

    public static func load() -> Snapshot? {
        guard let defaults = sharedDefaults(),
              let data = defaults.data(forKey: snapshotKey) else {
            return nil
        }

        let decoder = JSONDecoder()
        return try? decoder.decode(Snapshot.self, from: data)
    }

    public static func clear() {
        guard let defaults = sharedDefaults() else {
            return
        }
        defaults.removeObject(forKey: snapshotKey)
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
