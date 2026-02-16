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
            UsageMetricsView(usage: usage, style: layout.metricsStyle)
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
        }
    }
}
