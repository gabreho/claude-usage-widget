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

        completion(currentEntry(at: .now))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        let now = Date()
        let entry = currentEntry(at: now)
        let refreshDate = now.addingTimeInterval(ClaudeUsageWidgetTimeline.refreshInterval)
        completion(Timeline(entries: [entry], policy: .after(refreshDate)))
    }

    private func currentEntry(at date: Date) -> ClaudeUsageEntry {
        ClaudeUsageEntry(date: date, snapshot: UsageWidgetSharedStore.load(), isPlaceholder: false)
    }
}

private struct ClaudeUsageWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family

    let entry: ClaudeUsageEntry

    private var usage: UsageResponse? {
        entry.snapshot?.usage
    }

    var body: some View {
        Group {
            switch family {
            case .systemMedium:
                mediumBody
            default:
                smallBody
            }
        }
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

    private var smallBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerText

            if let usage {
                UsageMetricsView(usage: usage, style: .widgetCompact)
            } else {
                unavailableText
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var mediumBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerText

            if let usage {
                UsageMetricsView(usage: usage, style: .widgetProgress)

                if let fetchedAt = entry.snapshot?.fetchedAt {
                    Text("Updated \(fetchedAt, style: .relative) ago")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else {
                unavailableText
            }

            Spacer(minLength: 0)
        }
        .padding()
    }

    private var headerText: some View {
        Text("Claude Usage")
            .font(.headline)
    }

    private var unavailableText: some View {
        Text(entry.isPlaceholder ? "Usage preview" : "Open the app to sign in and refresh usage.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
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
        .description("Shows session and weekly Claude usage from the iOS app cache.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
