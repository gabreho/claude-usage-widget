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

            async let claudeResult = UsageService.fetchUsage(provider: .claude)
            async let codexResult = UsageService.fetchUsage(provider: .codex)
            let claudeUsage = try? await claudeResult
            let codexUsage = try? await codexResult

            let snapshot: UsageWidgetSharedStore.Snapshot?
            if claudeUsage != nil || codexUsage != nil {
                let fetched = UsageWidgetSharedStore.Snapshot(usage: claudeUsage, codexUsage: codexUsage, fetchedAt: now)
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

    /// Provider sections for the widget. The small family shows a single provider (Claude preferred)
    /// for space; the medium family stacks every signed-in provider.
    private var sections: [ProviderUsageSection] {
        let claude = entry.snapshot?.usage
        let codex = entry.snapshot?.codexUsage

        var result: [ProviderUsageSection] = []
        if let claude {
            result.append(ProviderUsageSection(provider: .claude, usage: claude))
        }
        if let codex {
            result.append(ProviderUsageSection(provider: .codex, usage: codex))
        }

        if family != .systemMedium {
            return Array(result.prefix(1))
        }
        return result
    }

    var body: some View {
        UsageDashboardView(
            style: dashboardStyle,
            title: sections.count > 1 ? "Usage" : (sections.first?.provider.displayName ?? "Usage"),
            sections: sections,
            isLoading: false,
            lastUpdated: entry.snapshot?.fetchedAt,
            unavailableMessage: unavailableMessage
        )
        .padding()
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: gradientColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    private var gradientColors: [Color] {
        #if os(iOS)
        [
            Color(uiColor: .secondarySystemBackground),
            Color(uiColor: .systemBackground)
        ]
        #elseif os(macOS)
        [
            Color(nsColor: .windowBackgroundColor),
            Color(nsColor: .controlBackgroundColor)
        ]
        #endif
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
