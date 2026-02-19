import SwiftUI

public enum UsageMetricStyle {
    case popover
    case card
    case widgetCompact
    case widgetProgress
}

public struct UsageMetricsView: View {
    private let usage: UsageResponse
    private let style: UsageMetricStyle

    public init(usage: UsageResponse, style: UsageMetricStyle) {
        self.usage = usage
        self.style = style
    }

    public var body: some View {
        let metrics = metricItems()

        VStack(alignment: .leading, spacing: layout.rowSpacing) {
            ForEach(metrics) { item in
                if layout.wrapInCard {
                    UsageMetricCard(
                        label: item.label,
                        limit: item.limit,
                        layout: layout
                    )
                } else {
                    UsageMetricRow(
                        label: item.label,
                        limit: item.limit,
                        layout: layout
                    )
                }
            }
        }
    }

    private var layout: MetricLayout {
        MetricLayout(style: style)
    }

    private func metricItems() -> [MetricItem] {
        var items: [MetricItem] = [
            MetricItem(
                label: layout.useShortPrimaryLabels ? "Session" : "Session (5-hour)",
                limit: usage.fiveHour
            ),
            MetricItem(
                label: layout.useShortPrimaryLabels ? "Weekly" : "Weekly (7-day)",
                limit: usage.sevenDay
            )
        ]

        guard layout.includeModelBuckets else {
            return items
        }

        if let opus = usage.sevenDayOpus {
            items.append(MetricItem(label: "Opus (7-day)", limit: opus))
        }

        if let sonnet = usage.sevenDaySonnet {
            items.append(MetricItem(label: "Sonnet (7-day)", limit: sonnet))
        }

        return items
    }
}

private struct MetricItem: Identifiable {
    let label: String
    let limit: UsageLimit

    var id: String { label }
}

private struct MetricLayout {
    let rowSpacing: CGFloat
    let contentSpacing: CGFloat
    let showProgress: Bool
    let showResetDate: Bool
    let wrapInCard: Bool
    let includeModelBuckets: Bool
    let useShortPrimaryLabels: Bool
    let roundPercent: Bool
    let labelFont: Font
    let valueFont: Font
    let resetFont: Font

    init(style: UsageMetricStyle) {
        switch style {
        case .popover:
            rowSpacing = 12
            contentSpacing = 4
            showProgress = true
            showResetDate = true
            wrapInCard = false
            includeModelBuckets = true
            useShortPrimaryLabels = false
            roundPercent = false
            labelFont = .subheadline.weight(.medium)
            valueFont = .subheadline.monospacedDigit()
            resetFont = .caption2
        case .card:
            rowSpacing = 12
            contentSpacing = 8
            showProgress = true
            showResetDate = true
            wrapInCard = true
            includeModelBuckets = true
            useShortPrimaryLabels = false
            roundPercent = false
            labelFont = .headline
            valueFont = .headline.monospacedDigit()
            resetFont = .caption
        case .widgetCompact:
            rowSpacing = 8
            contentSpacing = 4
            showProgress = false
            showResetDate = false
            wrapInCard = false
            includeModelBuckets = false
            useShortPrimaryLabels = true
            roundPercent = true
            labelFont = .subheadline.weight(.medium)
            valueFont = .subheadline.monospacedDigit().weight(.semibold)
            resetFont = .caption2
        case .widgetProgress:
            rowSpacing = 10
            contentSpacing = 5
            showProgress = true
            showResetDate = true
            wrapInCard = false
            includeModelBuckets = false
            useShortPrimaryLabels = false
            roundPercent = true
            labelFont = .subheadline.weight(.medium)
            valueFont = .subheadline.monospacedDigit().weight(.semibold)
            resetFont = .caption2
        }
    }
}

private struct UsageMetricCard: View {
    let label: String
    let limit: UsageLimit
    let layout: MetricLayout

    var body: some View {
        UsageMetricRow(label: label, limit: limit, layout: layout)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                .thinMaterial,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
    }
}

private struct UsageMetricRow: View {
    let label: String
    let limit: UsageLimit
    let layout: MetricLayout

    var body: some View {
        VStack(alignment: .leading, spacing: layout.contentSpacing) {
            HStack {
                Text(label)
                    .font(layout.labelFont)
                Spacer()
                Text(percentText)
                    .font(layout.valueFont)
                    .foregroundStyle(tintColor)
            }

            if layout.showProgress {
                ProgressView(value: limit.utilization, total: 100)
                    .tint(tintColor)
            }

            if layout.showResetDate,
               let resetDate = limit.resetDate,
               resetDate > Date() {
                Text("Resets \(resetDate, style: .relative)")
                    .font(layout.resetFont)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var percentText: String {
        if layout.roundPercent {
            return "\(Int(limit.utilization.rounded()))%"
        } else {
            return String(format: "%.1f%%", limit.utilization)
        }
    }

    private var tintColor: Color {
        switch limit.tier {
        case .green:
            return .green
        case .yellow:
            return .yellow
        case .red:
            return .red
        }
    }
}
