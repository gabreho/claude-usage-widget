import Foundation

public enum UsageWidgetSharedStore {
    public static let appGroupIdentifier = "group.com.gabreho.claude-usage"
    public static let widgetKind = "ClaudeUsageWidget"

    private static let snapshotKeyV2 = "claude_usage_widget_snapshot_v2"
    private static let snapshotKeyV1 = "claude_usage_widget_snapshot_v1"

    public struct Snapshot: Codable, Sendable {
        /// Claude usage, when signed in to Claude. Optional so a Codex-only user still has a snapshot.
        public let usage: UsageResponse?
        /// Codex usage, when signed in to Codex. Absent in legacy (v1) snapshots.
        public let codexUsage: UsageResponse?
        public let fetchedAt: Date

        public init(usage: UsageResponse?, codexUsage: UsageResponse? = nil, fetchedAt: Date) {
            self.usage = usage
            self.codexUsage = codexUsage
            self.fetchedAt = fetchedAt
        }
    }

    public static func save(usage: UsageResponse?, codexUsage: UsageResponse? = nil, fetchedAt: Date = Date()) {
        save(Snapshot(usage: usage, codexUsage: codexUsage, fetchedAt: fetchedAt))
    }

    public static func save(_ snapshot: Snapshot) {
        guard let defaults = sharedDefaults() else {
            return
        }

        let encoder = JSONEncoder()
        guard let data = try? encoder.encode(snapshot) else {
            return
        }

        defaults.set(data, forKey: snapshotKeyV2)
    }

    public static func load() -> Snapshot? {
        guard let defaults = sharedDefaults() else {
            return nil
        }

        let decoder = JSONDecoder()

        if let data = defaults.data(forKey: snapshotKeyV2),
           let snapshot = try? decoder.decode(Snapshot.self, from: data) {
            return snapshot
        }

        // Migration: a legacy v1 snapshot is Claude-only; the optional `codexUsage` decodes as nil.
        if let legacy = defaults.data(forKey: snapshotKeyV1),
           let snapshot = try? decoder.decode(Snapshot.self, from: legacy) {
            return snapshot
        }

        return nil
    }

    public static func clear() {
        guard let defaults = sharedDefaults() else {
            return
        }
        defaults.removeObject(forKey: snapshotKeyV2)
        defaults.removeObject(forKey: snapshotKeyV1)
    }

    private static func sharedDefaults() -> UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
