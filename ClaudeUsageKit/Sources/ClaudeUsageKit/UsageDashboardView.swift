import SwiftUI

public enum UsageDashboardStyle {
    case popover
    case iosHome
    case widgetSmall
    case widgetMedium
}

public struct UsageDashboardView<HeaderAccessory: View, FooterAccessory: View>: View {
    private let style: UsageDashboardStyle
    private let usage: UsageResponse?
    private let errorMessage: String?
    private let isLoading: Bool
    private let shouldOfferInAppLogin: Bool
    private let lastUpdated: Date?
    private let unavailableMessage: String?
    private let onLogin: (() -> Void)?
    private let headerAccessory: () -> HeaderAccessory
    private let footerAccessory: () -> FooterAccessory

    public init(
        style: UsageDashboardStyle,
        usage: UsageResponse?,
        errorMessage: String? = nil,
        isLoading: Bool = false,
        shouldOfferInAppLogin: Bool = false,
        lastUpdated: Date? = nil,
        unavailableMessage: String? = nil,
        onLogin: (() -> Void)? = nil,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder footerAccessory: @escaping () -> FooterAccessory
    ) {
        self.style = style
        self.usage = usage
        self.errorMessage = errorMessage
        self.isLoading = isLoading
        self.shouldOfferInAppLogin = shouldOfferInAppLogin
        self.lastUpdated = lastUpdated
        self.unavailableMessage = unavailableMessage
        self.onLogin = onLogin
        self.headerAccessory = headerAccessory
        self.footerAccessory = footerAccessory
    }

    public var body: some View {
        let layout = DashboardLayout(style: style)

        VStack(alignment: .leading, spacing: layout.stackSpacing) {
            headerSection(layout: layout)

            if layout.showHeaderDivider {
                Divider()
            }

            if let errorMessage {
                errorSection(errorMessage, layout: layout)
            }

            contentSection(layout: layout)

            if layout.showFooterDivider {
                Divider()
            }

            if shouldShowFooter(layout: layout) {
                footerSection(layout: layout)
            }

            if layout.addBottomSpacer {
                Spacer(minLength: 0)
            }
        }
    }

    private func shouldShowFooter(layout: DashboardLayout) -> Bool {
        layout.alwaysShowFooter
            || (layout.showsLastUpdated && lastUpdated != nil)
    }

    @ViewBuilder
    private func headerSection(layout: DashboardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.headerSupplementarySpacing) {
            HStack {
                Text("Claude Usage")
                    .font(layout.titleFont)
                Spacer()
                headerAccessory()
            }

            if usage == nil {
                if layout.showLoadingInHeader && isLoading {
                    if let loadingLabel = layout.headerLoadingLabel {
                        ProgressView(loadingLabel)
                            .font(layout.headerSupplementaryFont)
                    } else {
                        ProgressView()
                    }
                } else if layout.showUnavailableInHeader,
                          !shouldOfferInAppLogin,
                          let message = unavailableMessage ?? layout.defaultUnavailableMessage {
                    Text(message)
                        .font(layout.headerSupplementaryFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func errorSection(_ message: String, layout: DashboardLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(message, systemImage: layout.errorIcon)
                .font(layout.errorFont)
                .foregroundStyle(.red)

            loginButton(style: layout.errorLoginButtonStyle)
        }
    }

    @ViewBuilder
    private func contentSection(layout: DashboardLayout) -> some View {
        if let usage {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                UsageMetricsView(usage: usage, style: layout.metricsStyle)
                if layout.showExtraUsage, let extra = usage.extraUsage, extra.hasData {
                    Divider()
                    ExtraUsageSectionView(extra: extra, wrapInCard: layout.extraWrapInCard)
                }
            }
        } else if layout.showLoadingInContent && isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if shouldOfferInAppLogin,
                  layout.emptyLoginButtonStyle != .hidden,
                  onLogin != nil {
            loginButton(style: layout.emptyLoginButtonStyle)
        } else if !layout.showUnavailableInHeader,
                  let message = unavailableMessage ?? layout.defaultUnavailableMessage {
            Text(message)
                .font(layout.unavailableFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    private func footerSection(layout: DashboardLayout) -> some View {
        HStack {
            if layout.showsLastUpdated, let lastUpdated {
                Text("Updated \(lastUpdated, style: .relative) ago")
                    .font(layout.footerTimestampFont)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            footerAccessory()
        }
    }

    @ViewBuilder
    private func loginButton(style: DashboardLoginButtonStyle) -> some View {
        if shouldOfferInAppLogin,
           let onLogin,
           style != .hidden {
            switch style {
            case .hidden:
                EmptyView()
            case .borderlessCaption:
                Button(action: onLogin) {
                    Label("Sign In with Claude", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderless)
                .font(.caption)
            case .borderedProminent:
                Button(action: onLogin) {
                    Label("Sign In with Claude", systemImage: "person.badge.key")
                }
                .buttonStyle(.borderedProminent)
            case .borderedProminentFullWidth:
                Button(action: onLogin) {
                    Label("Sign In with Claude", systemImage: "person.badge.key")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

public extension UsageDashboardView where HeaderAccessory == EmptyView, FooterAccessory == EmptyView {
    init(
        style: UsageDashboardStyle,
        usage: UsageResponse?,
        errorMessage: String? = nil,
        isLoading: Bool = false,
        shouldOfferInAppLogin: Bool = false,
        lastUpdated: Date? = nil,
        unavailableMessage: String? = nil,
        onLogin: (() -> Void)? = nil
    ) {
        self.init(
            style: style,
            usage: usage,
            errorMessage: errorMessage,
            isLoading: isLoading,
            shouldOfferInAppLogin: shouldOfferInAppLogin,
            lastUpdated: lastUpdated,
            unavailableMessage: unavailableMessage,
            onLogin: onLogin,
            headerAccessory: { EmptyView() },
            footerAccessory: { EmptyView() }
        )
    }
}

private enum DashboardLoginButtonStyle {
    case hidden
    case borderlessCaption
    case borderedProminent
    case borderedProminentFullWidth
}

private struct DashboardLayout {
    let stackSpacing: CGFloat
    let headerSupplementarySpacing: CGFloat
    let showHeaderDivider: Bool
    let showFooterDivider: Bool
    let addBottomSpacer: Bool

    let titleFont: Font
    let headerSupplementaryFont: Font
    let errorIcon: String
    let errorFont: Font

    let metricsStyle: UsageMetricStyle

    let showLoadingInHeader: Bool
    let headerLoadingLabel: String?
    let showLoadingInContent: Bool

    let showUnavailableInHeader: Bool
    let defaultUnavailableMessage: String?
    let unavailableFont: Font

    let errorLoginButtonStyle: DashboardLoginButtonStyle
    let emptyLoginButtonStyle: DashboardLoginButtonStyle

    let alwaysShowFooter: Bool
    let showsLastUpdated: Bool
    let footerTimestampFont: Font

    let showExtraUsage: Bool
    let extraWrapInCard: Bool

    init(style: UsageDashboardStyle) {
        switch style {
        case .popover:
            stackSpacing = 12
            headerSupplementarySpacing = 8
            showHeaderDivider = true
            showFooterDivider = true
            addBottomSpacer = false

            titleFont = .headline
            headerSupplementaryFont = .subheadline
            errorIcon = "exclamationmark.triangle"
            errorFont = .caption

            metricsStyle = .popover

            showLoadingInHeader = false
            headerLoadingLabel = nil
            showLoadingInContent = true

            showUnavailableInHeader = false
            defaultUnavailableMessage = nil
            unavailableFont = .caption

            errorLoginButtonStyle = .borderlessCaption
            emptyLoginButtonStyle = .borderedProminentFullWidth

            alwaysShowFooter = true
            showsLastUpdated = true
            footerTimestampFont = .caption2

            showExtraUsage = true
            extraWrapInCard = false
        case .iosHome:
            stackSpacing = 16
            headerSupplementarySpacing = 8
            showHeaderDivider = false
            showFooterDivider = false
            addBottomSpacer = false

            titleFont = .title2.weight(.semibold)
            headerSupplementaryFont = .subheadline
            errorIcon = "exclamationmark.triangle.fill"
            errorFont = .footnote

            metricsStyle = .card

            showLoadingInHeader = true
            headerLoadingLabel = "Loading usage…"
            showLoadingInContent = false

            showUnavailableInHeader = true
            defaultUnavailableMessage = "No usage data yet. Pull to refresh or try again in a moment."
            unavailableFont = .subheadline

            errorLoginButtonStyle = .borderedProminentFullWidth
            emptyLoginButtonStyle = .hidden

            alwaysShowFooter = false
            showsLastUpdated = true
            footerTimestampFont = .caption

            showExtraUsage = true
            extraWrapInCard = true
        case .widgetSmall:
            stackSpacing = 10
            headerSupplementarySpacing = 6
            showHeaderDivider = false
            showFooterDivider = false
            addBottomSpacer = true

            titleFont = .headline
            headerSupplementaryFont = .caption
            errorIcon = "exclamationmark.triangle.fill"
            errorFont = .caption

            metricsStyle = .widgetCompact

            showLoadingInHeader = false
            headerLoadingLabel = nil
            showLoadingInContent = false

            showUnavailableInHeader = false
            defaultUnavailableMessage = nil
            unavailableFont = .caption

            errorLoginButtonStyle = .hidden
            emptyLoginButtonStyle = .hidden

            alwaysShowFooter = false
            showsLastUpdated = false
            footerTimestampFont = .caption2

            showExtraUsage = false
            extraWrapInCard = false
        case .widgetMedium:
            stackSpacing = 10
            headerSupplementarySpacing = 6
            showHeaderDivider = false
            showFooterDivider = false
            addBottomSpacer = true

            titleFont = .headline
            headerSupplementaryFont = .caption
            errorIcon = "exclamationmark.triangle.fill"
            errorFont = .caption

            metricsStyle = .widgetProgress

            showLoadingInHeader = false
            headerLoadingLabel = nil
            showLoadingInContent = false

            showUnavailableInHeader = false
            defaultUnavailableMessage = nil
            unavailableFont = .caption

            errorLoginButtonStyle = .hidden
            emptyLoginButtonStyle = .hidden

            alwaysShowFooter = false
            showsLastUpdated = true
            footerTimestampFont = .caption2

            showExtraUsage = false
            extraWrapInCard = false
        }
    }
}

private struct ExtraUsageSectionView: View {
    let extra: ExtraUsage
    let wrapInCard: Bool

    var body: some View {
        if wrapInCard {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    .thinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
        } else {
            content
        }
    }

    @ViewBuilder
    private var content: some View {
        VStack(alignment: .leading, spacing: wrapInCard ? 8 : 4) {
            HStack {
                Text("Extra Usage")
                    .font(wrapInCard ? .headline : .subheadline.weight(.medium))
                Spacer()
                if let usedCredits = extra.effectiveUsedCredits {
                    Group {
                        if let monthlyLimit = extra.effectiveMonthlyLimit {
                            Text("\(usd(usedCredits)) / \(usd(monthlyLimit))")
                        } else {
                            Text(usd(usedCredits))
                        }
                    }
                    .font(wrapInCard ? .headline.monospacedDigit() : .subheadline.monospacedDigit())
                    .foregroundStyle(utilizationColor)
                }
            }

            if let usedCredits = extra.effectiveUsedCredits,
               let monthlyLimit = extra.effectiveMonthlyLimit,
               monthlyLimit > 0 {
                ProgressView(value: min(usedCredits, monthlyLimit), total: monthlyLimit)
                    .tint(utilizationColor)
            }

            if let utilization = extra.effectiveUtilization {
                Text("\(percent(utilization)) utilized")
                    .font(wrapInCard ? .caption : .caption2)
                    .foregroundStyle(.secondary)
            }

            if let remaining = extra.remainingCredits {
                Text("\(usd(remaining)) remaining")
                    .font(wrapInCard ? .caption : .caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var utilizationColor: Color {
        let ratio: Double
        if let utilization = extra.effectiveUtilization {
            ratio = utilization / 100
        } else if let usedCredits = extra.effectiveUsedCredits,
                  let monthlyLimit = extra.effectiveMonthlyLimit,
                  monthlyLimit > 0 {
            ratio = usedCredits / monthlyLimit
        } else {
            return .primary
        }

        switch ratio {
        case ..<0.5: return .green
        case ..<0.8: return .yellow
        default: return .red
        }
    }

    // The API returns extra usage values in cent-like units (e.g. 1103 => $11.03).
    private func usd(_ amount: Double) -> String {
        String(format: "$%.2f", amount / 100)
    }

    private func percent(_ value: Double) -> String {
        if value.rounded() == value {
            return String(format: "%.0f%%", value)
        }
        return String(format: "%.1f%%", value)
    }
}
