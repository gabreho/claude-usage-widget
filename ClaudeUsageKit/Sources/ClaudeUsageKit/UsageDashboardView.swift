import SwiftUI

public enum UsageDashboardStyle {
    case popover
    case iosHome
    case widgetSmall
    case widgetMedium
}

/// One provider's slice of the dashboard: its usage (if loaded), error, and sign-in affordance.
public struct ProviderUsageSection: Identifiable {
    public let provider: UsageProvider
    public let usage: UsageResponse?
    public let errorMessage: String?
    public let shouldOfferInAppLogin: Bool
    public let onLogin: (() -> Void)?

    public var id: String { provider.rawValue }

    public init(
        provider: UsageProvider,
        usage: UsageResponse?,
        errorMessage: String? = nil,
        shouldOfferInAppLogin: Bool = false,
        onLogin: (() -> Void)? = nil
    ) {
        self.provider = provider
        self.usage = usage
        self.errorMessage = errorMessage
        self.shouldOfferInAppLogin = shouldOfferInAppLogin
        self.onLogin = onLogin
    }
}

public struct UsageDashboardView<HeaderAccessory: View, FooterAccessory: View>: View {
    private let style: UsageDashboardStyle
    private let title: String
    private let sections: [ProviderUsageSection]
    private let isLoading: Bool
    private let lastUpdated: Date?
    private let unavailableMessage: String?
    private let headerAccessory: () -> HeaderAccessory
    private let footerAccessory: () -> FooterAccessory

    /// Multi-provider initializer: renders one labeled section per provider, stacked vertically.
    public init(
        style: UsageDashboardStyle,
        title: String = "Usage",
        sections: [ProviderUsageSection],
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        unavailableMessage: String? = nil,
        @ViewBuilder headerAccessory: @escaping () -> HeaderAccessory,
        @ViewBuilder footerAccessory: @escaping () -> FooterAccessory
    ) {
        self.style = style
        self.title = title
        self.sections = sections
        self.isLoading = isLoading
        self.lastUpdated = lastUpdated
        self.unavailableMessage = unavailableMessage
        self.headerAccessory = headerAccessory
        self.footerAccessory = footerAccessory
    }

    /// Backward-compatible single-provider (Claude) initializer.
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
        self.init(
            style: style,
            title: "Claude Usage",
            sections: [
                ProviderUsageSection(
                    provider: .claude,
                    usage: usage,
                    errorMessage: errorMessage,
                    shouldOfferInAppLogin: shouldOfferInAppLogin,
                    onLogin: onLogin
                )
            ],
            isLoading: isLoading,
            lastUpdated: lastUpdated,
            unavailableMessage: unavailableMessage,
            headerAccessory: headerAccessory,
            footerAccessory: footerAccessory
        )
    }

    /// True when at least one section has loaded usage data.
    private var hasAnyUsage: Bool {
        sections.contains { $0.usage != nil }
    }

    /// Show per-provider titles only when more than one provider is on screen.
    private var showSectionTitles: Bool {
        sections.count > 1
    }

    public var body: some View {
        let layout = DashboardLayout(style: style)

        VStack(alignment: .leading, spacing: layout.stackSpacing) {
            headerSection(layout: layout)

            if layout.showHeaderDivider {
                Divider()
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
                Text(title)
                    .font(layout.titleFont)
                Spacer()
                headerAccessory()
            }

            if !hasAnyUsage {
                if layout.showLoadingInHeader && isLoading {
                    if let loadingLabel = layout.headerLoadingLabel {
                        ProgressView(loadingLabel)
                            .font(layout.headerSupplementaryFont)
                    } else {
                        ProgressView()
                    }
                } else if layout.showUnavailableInHeader,
                          !sections.contains(where: { $0.shouldOfferInAppLogin }),
                          let message = unavailableMessage ?? layout.defaultUnavailableMessage {
                    Text(message)
                        .font(layout.headerSupplementaryFont)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func contentSection(layout: DashboardLayout) -> some View {
        if hasAnyUsage || sections.contains(where: { $0.shouldOfferInAppLogin || $0.errorMessage != nil }) {
            VStack(alignment: .leading, spacing: layout.stackSpacing) {
                ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                    if index > 0 {
                        Divider()
                    }
                    providerSection(section, layout: layout)
                }
            }
        } else if layout.showLoadingInContent && isLoading {
            ProgressView()
                .frame(maxWidth: .infinity)
        } else if !layout.showUnavailableInHeader,
                  let message = unavailableMessage ?? layout.defaultUnavailableMessage {
            Text(message)
                .font(layout.unavailableFont)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
        }
    }

    @ViewBuilder
    private func providerSection(_ section: ProviderUsageSection, layout: DashboardLayout) -> some View {
        VStack(alignment: .leading, spacing: layout.headerSupplementarySpacing) {
            if showSectionTitles {
                Text(section.provider.displayName)
                    .font(layout.sectionTitleFont)
                    .foregroundStyle(.secondary)
            }

            if let message = section.errorMessage {
                Label(message, systemImage: layout.errorIcon)
                    .font(layout.errorFont)
                    .foregroundStyle(.red)
            }

            if let usage = section.usage {
                UsageMetricsView(usage: usage, style: layout.metricsStyle)
                if layout.showExtraUsage, let extra = usage.extraUsage, extra.hasData {
                    Divider()
                    ExtraUsageSectionView(extra: extra, wrapInCard: layout.extraWrapInCard)
                }
            } else if section.shouldOfferInAppLogin, section.onLogin != nil {
                let buttonStyle = section.errorMessage != nil ? layout.errorLoginButtonStyle : layout.emptyLoginButtonStyle
                loginButton(for: section, style: buttonStyle)
            }
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
    private func loginButton(for section: ProviderUsageSection, style: DashboardLoginButtonStyle) -> some View {
        if section.shouldOfferInAppLogin,
           let onLogin = section.onLogin,
           style != .hidden {
            let label = Label(section.provider.signInLabel, systemImage: section.provider.signInIcon)
            switch style {
            case .hidden:
                EmptyView()
            case .borderlessCaption:
                Button(action: onLogin) { label }
                    .buttonStyle(.borderless)
                    .font(.caption)
            case .borderedProminent:
                Button(action: onLogin) { label }
                    .buttonStyle(.borderedProminent)
            case .borderedProminentFullWidth:
                Button(action: onLogin) {
                    label.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }
}

public extension UsageDashboardView where HeaderAccessory == EmptyView, FooterAccessory == EmptyView {
    init(
        style: UsageDashboardStyle,
        title: String = "Usage",
        sections: [ProviderUsageSection],
        isLoading: Bool = false,
        lastUpdated: Date? = nil,
        unavailableMessage: String? = nil
    ) {
        self.init(
            style: style,
            title: title,
            sections: sections,
            isLoading: isLoading,
            lastUpdated: lastUpdated,
            unavailableMessage: unavailableMessage,
            headerAccessory: { EmptyView() },
            footerAccessory: { EmptyView() }
        )
    }

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
    let sectionTitleFont: Font
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
            sectionTitleFont = .caption.weight(.semibold)
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
            sectionTitleFont = .headline
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
            sectionTitleFont = .caption2.weight(.semibold)
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
            sectionTitleFont = .caption2.weight(.semibold)
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
