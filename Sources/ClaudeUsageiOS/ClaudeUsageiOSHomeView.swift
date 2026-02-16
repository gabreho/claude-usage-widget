import ClaudeUsageKit
import SwiftUI
import WidgetKit

struct ClaudeUsageiOSHomeView: View {
    @StateObject private var viewModel = ClaudeUsageiOSViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    headerSection

                    if let error = viewModel.error {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(error, systemImage: "exclamationmark.triangle.fill")
                                .font(.footnote)
                                .foregroundStyle(.red)

                            if viewModel.shouldOfferInAppLogin {
                                Button(action: { viewModel.startInAppOAuthLogin() }) {
                                    Label("Sign In with Claude", systemImage: "person.badge.key")
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    usageSection

                    footerSection
                }
                .padding()
            }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading || viewModel.isCompletingOAuthLogin)
                }
            }
        }
        .fullScreenCover(isPresented: $viewModel.isShowingOAuthLogin) {
            if let authorizationURL = viewModel.oauthAuthorizationURL {
                OAuthLoginSheet(
                    authorizationURL: authorizationURL,
                    isCompletingLogin: viewModel.isCompletingOAuthLogin,
                    onCancel: { viewModel.cancelInAppOAuthLogin() },
                    onCodeReceived: { code, state in
                        viewModel.completeInAppOAuthLogin(code: code, returnedState: state)
                    },
                    onFailure: { message in
                        viewModel.handleInAppOAuthFailure(message)
                    }
                )
            }
        }
    }

    @ViewBuilder
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claude Usage")
                .font(.title2.weight(.semibold))

            if viewModel.isLoading && viewModel.usage == nil {
                ProgressView("Loading usage…")
                    .font(.subheadline)
            } else if viewModel.usage == nil && !viewModel.shouldOfferInAppLogin {
                Text("No usage data yet. Pull to refresh or try again in a moment.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var usageSection: some View {
        if let usage = viewModel.usage {
            VStack(spacing: 12) {
                UsageLimitCard(title: "Session (5-hour)", limit: usage.fiveHour)
                UsageLimitCard(title: "Weekly (7-day)", limit: usage.sevenDay)

                if let opus = usage.sevenDayOpus, opus.utilization > 0 {
                    UsageLimitCard(title: "Opus (7-day)", limit: opus)
                }

                if let sonnet = usage.sevenDaySonnet, sonnet.utilization > 0 {
                    UsageLimitCard(title: "Sonnet (7-day)", limit: sonnet)
                }
            }
        }
    }

    @ViewBuilder
    private var footerSection: some View {
        if let lastUpdated = viewModel.lastUpdated {
            Text("Updated \(lastUpdated, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct UsageLimitCard: View {
    let title: String
    let limit: UsageLimit

    private var tintColor: Color {
        switch limit.tier {
        case .green: return .green
        case .yellow: return .yellow
        case .red: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Text("\(Int(limit.utilization))%")
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(tintColor)
            }

            ProgressView(value: limit.utilization, total: 100)
                .tint(tintColor)

            if let resetDate = limit.resetDate, resetDate > Date() {
                Text("Resets \(resetDate, style: .relative)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

@MainActor
private final class ClaudeUsageiOSViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var error: String?
    @Published var isLoading = false
    @Published var isCompletingOAuthLogin = false
    @Published var lastUpdated: Date?
    @Published var oauthAuthorizationURL: URL?
    @Published var isShowingOAuthLogin = false

    private let refreshInterval: TimeInterval = 300
    private var refreshTimer: Timer?
    private var startedAutoRefresh = false
    private var lastServiceError: UsageServiceError?
    private var oauthAuthorizationSession: UsageService.OAuthAuthorizationSession?

    init() {
        // Avoid network/keychain side effects during SwiftUI canvas previews.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return
        }
        startAutoRefreshIfNeeded()
    }

    var shouldOfferInAppLogin: Bool {
        lastServiceError?.supportsInAppLoginRecovery == true
    }

    func refresh() {
        guard !isLoading, !isCompletingOAuthLogin else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await UsageService.fetchUsage()
                let refreshedAt = Date()
                self.usage = result
                self.lastUpdated = refreshedAt
                UsageWidgetSharedStore.save(usage: result, fetchedAt: refreshedAt)
                WidgetCenter.shared.reloadTimelines(ofKind: UsageWidgetSharedStore.widgetKind)
                self.error = nil
                self.lastServiceError = nil
            } catch {
                self.lastServiceError = error as? UsageServiceError
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func startInAppOAuthLogin() {
        let session = UsageService.createOAuthAuthorizationSession()
        oauthAuthorizationSession = session
        oauthAuthorizationURL = session.authorizationURL
        isShowingOAuthLogin = true
        error = nil
    }

    func cancelInAppOAuthLogin() {
        isShowingOAuthLogin = false
        oauthAuthorizationURL = nil
        oauthAuthorizationSession = nil
        isCompletingOAuthLogin = false
    }

    func completeInAppOAuthLogin(code: String, returnedState: String?) {
        guard let session = oauthAuthorizationSession else {
            error = "OAuth session expired. Please try signing in again."
            return
        }

        if let returnedState,
           !returnedState.isEmpty,
           returnedState != session.state {
            error = "OAuth state mismatch. Please try signing in again."
            cancelInAppOAuthLogin()
            return
        }

        isCompletingOAuthLogin = true
        error = nil

        Task {
            do {
                try await UsageService.completeOAuthAuthorization(
                    code: code,
                    state: session.state,
                    codeVerifier: session.codeVerifier
                )
                self.lastServiceError = nil
                self.cancelInAppOAuthLogin()
                self.refresh()
            } catch {
                self.lastServiceError = error as? UsageServiceError
                self.error = error.localizedDescription
                self.cancelInAppOAuthLogin()
            }
        }
    }

    func handleInAppOAuthFailure(_ message: String) {
        error = message
        cancelInAppOAuthLogin()
    }

    private func startAutoRefreshIfNeeded() {
        guard !startedAutoRefresh else { return }
        startedAutoRefresh = true
        refresh()
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: refreshInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }
}

#Preview {
    ClaudeUsageiOSHomeView()
}
