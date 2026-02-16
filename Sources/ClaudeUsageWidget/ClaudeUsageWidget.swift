import SwiftUI
import WidgetKit

private struct ClaudeUsageEntry: TimelineEntry {
    let date: Date
    let summary: String
}

private struct ClaudeUsageProvider: TimelineProvider {
    func placeholder(in context: Context) -> ClaudeUsageEntry {
        ClaudeUsageEntry(date: .now, summary: "OAuth setup pending")
    }

    func getSnapshot(in context: Context, completion: @escaping (ClaudeUsageEntry) -> Void) {
        completion(ClaudeUsageEntry(date: .now, summary: "OAuth setup pending"))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ClaudeUsageEntry>) -> Void) {
        let entry = ClaudeUsageEntry(date: .now, summary: "Provider scaffold ready")
        let refresh = Date().addingTimeInterval(30 * 60)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }
}

private struct ClaudeUsageWidgetEntryView: View {
    let entry: ClaudeUsageEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Usage")
                .font(.headline)
            Text(entry.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .padding()
    }
}

@main
struct ClaudeUsageWidget: Widget {
    private let kind = "ClaudeUsageWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ClaudeUsageProvider()) { entry in
            ClaudeUsageWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Scaffolded iOS widget host for upcoming provider and auth wiring.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
