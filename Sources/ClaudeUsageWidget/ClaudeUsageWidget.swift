import ClaudeUsageKit
import SwiftUI
import WidgetKit

private enum ClaudeUsageWidgetTimeline {
    static let refreshInterval: TimeInterval = 15 * 60
}

private struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageWidgetSharedStore.Snapshot?
    let isPlaceholder: Bool
}

private struct ClaudeUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(date: .now, snapshot: nil, isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        if context.isPreview {
            completion(ClaudeUsageEntry(date: .now, snapshot: nil, isPlaceholder: true))
            return
        }

        let snapshot = UsageWidgetSharedStore.load()
        completion(ClaudeUsageEntry(date: .now, snapshot: snapshot, isPlaceholder: false))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        Task {
            let now = Date()
            let snapshot: UsageWidgetSharedStore.Snapshot?

            if let usage = try? await UsageService.fetchUsage() {
                let fetched = UsageWidgetSharedStore.Snapshot(usage: usage, fetchedAt: now)
                UsageWidgetSharedStore.save(fetched)
                snapshot = fetched
            } else {
                snapshot = UsageWidgetSharedStore.load()
            }

            let entry = ClaudeUsageEntry(date: now, snapshot: snapshot, isPlaceholder: false)
            let refreshDate = now.addingTimeInterval(ClaudeUsageWidgetTimeline.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(refreshDate)))
        }
    }
}

private struct ClaudeUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ClaudeUsageEntry

    private var usage: UsageResponse? {
        entry.snapshot?.usage
    }

    var body: some View {
        UsageDashboardView(
            style: dashboardStyle,
            usage: usage,
            errorMessage: nil,
            isLoading: false,
            shouldOfferInAppLogin: false,
            lastUpdated: entry.snapshot?.fetchedAt,
            unavailableMessage: unavailableMessage
        )
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [
                    Color(uiColor: .secondarySystemBackground),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var dashboardStyle: UsageDashboardStyle {
        switch family {
        case .systemMedium:
            return .widgetMedium
        default:
            return .widgetSmall
        }
    }

    private var unavailableMessage: String {
        entry.isPlaceholder
            ? "Usage preview"
            : "Open the app to sign in and refresh usage."
    }
}

@main
struct ClaudeUsageWidget: Widget {
    private let kind = UsageWidgetSharedStore.widgetKind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageProvider()) { entry in
            ClaudeUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Shows your current session and weekly Claude usage.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
