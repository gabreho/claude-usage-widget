import ClaudeUsageKit
import SwiftUI
import WidgetKit

struct ClaudeUsageiOSHomeView: View {
    @StateObject private var viewModel = ClaudeUsageiOSViewModel()
    @State private var isShowingPreferences = false

    var body: some View {
        NavigationStack {
            ScrollView {
                UsageDashboardView(
                    style: .iosHome,
                    title: "Usage",
                    sections: viewModel.sections,
                    isLoading: viewModel.isLoading,
                    lastUpdated: viewModel.lastUpdated,
                    unavailableMessage: "No usage data yet. Pull to refresh or try again in a moment."
                )
                .padding()
            }
            .navigationTitle("Usage")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { isShowingPreferences = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { viewModel.refresh() }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(viewModel.isLoading || viewModel.isCompletingOAuthLogin)
                }
            }
        }
        .sheet(isPresented: $isShowingPreferences) {
            PreferencesView(onSignOut: { provider in viewModel.handleSignOut(provider: provider) })
        }
        .fullScreenCover(isPresented: $viewModel.isShowingOAuthLogin) {
            if let provider = viewModel.loginProvider,
               let authorizationURL = viewModel.oauthAuthorizationURL {
                OAuthLoginView(
                    provider: provider,
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
}

@MainActor
private final class ClaudeUsageiOSViewModel: ObservableObject {
    @Published var claudeUsage: UsageResponse?
    @Published var codexUsage: UsageResponse?
    @Published var claudeError: String?
    @Published var codexError: String?
    @Published var isLoading = false
    @Published var isCompletingOAuthLogin = false
    @Published var lastUpdated: Date?
    @Published var oauthAuthorizationURL: URL?
    @Published var isShowingOAuthLogin = false
    @Published var loginProvider: UsageProvider?

    private let refreshInterval: TimeInterval = 300
    private var refreshTimer: Timer?
    private var resetTimer: Timer?
    private var startedAutoRefresh = false
    private var claudeServiceError: UsageServiceError?
    private var codexServiceError: UsageServiceError?
    private var oauthSession: UsageService.OAuthAuthorizationSession?

    init() {
        // Avoid network/keychain side effects during SwiftUI canvas previews.
        guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] != "1" else {
            return
        }
        startAutoRefreshIfNeeded()
    }

    var sections: [ProviderUsageSection] {
        [
            ProviderUsageSection(
                provider: .claude,
                usage: claudeUsage,
                errorMessage: claudeError,
                shouldOfferInAppLogin: claudeServiceError?.supportsInAppLoginRecovery == true,
                onLogin: { [weak self] in self?.startInAppOAuthLogin(provider: .claude) }
            ),
            ProviderUsageSection(
                provider: .codex,
                usage: codexUsage,
                errorMessage: codexError,
                shouldOfferInAppLogin: codexServiceError?.supportsInAppLoginRecovery == true,
                onLogin: { [weak self] in self?.startInAppOAuthLogin(provider: .codex) }
            )
        ]
    }

    func refresh() {
        guard !isLoading, !isCompletingOAuthLogin else { return }
        isLoading = true

        Task {
            async let claude: Void = fetch(.claude)
            async let codex: Void = fetch(.codex)
            _ = await (claude, codex)

            let refreshedAt = Date()
            self.lastUpdated = refreshedAt
            if self.claudeUsage != nil || self.codexUsage != nil {
                UsageWidgetSharedStore.save(
                    usage: self.claudeUsage,
                    codexUsage: self.codexUsage,
                    fetchedAt: refreshedAt
                )
                WidgetCenter.shared.reloadTimelines(ofKind: UsageWidgetSharedStore.widgetKind)
            }
            self.scheduleResetRefresh()
            self.isLoading = false
        }
    }

    private func fetch(_ provider: UsageProvider) async {
        do {
            let result = try await UsageService.fetchUsage(provider: provider)
            apply(usage: result, error: nil, serviceError: nil, for: provider)
        } catch {
            apply(usage: nil, error: error.localizedDescription, serviceError: error as? UsageServiceError, for: provider)
        }
    }

    private func apply(usage: UsageResponse?, error: String?, serviceError: UsageServiceError?, for provider: UsageProvider) {
        switch provider {
        case .claude:
            if let usage { claudeUsage = usage }
            claudeError = error
            claudeServiceError = serviceError
        case .codex:
            if let usage { codexUsage = usage }
            codexError = error
            codexServiceError = serviceError
        }
    }

    func handleSignOut(provider: UsageProvider) {
        UsageService.signOut(provider: provider)
        switch provider {
        case .claude:
            claudeUsage = nil
            claudeError = nil
            claudeServiceError = nil
        case .codex:
            codexUsage = nil
            codexError = nil
            codexServiceError = nil
        }
        refresh()
    }

    func startInAppOAuthLogin(provider: UsageProvider) {
        let session = UsageService.createOAuthAuthorizationSession(provider: provider)
        oauthSession = session
        loginProvider = provider
        oauthAuthorizationURL = session.authorizationURL
        isShowingOAuthLogin = true
        setError(nil, for: provider)
    }

    func cancelInAppOAuthLogin() {
        isShowingOAuthLogin = false
        oauthAuthorizationURL = nil
        oauthSession = nil
        loginProvider = nil
        isCompletingOAuthLogin = false
    }

    func completeInAppOAuthLogin(code: String, returnedState: String?) {
        guard let session = oauthSession else {
            return
        }
        let provider = session.provider

        if let returnedState, !returnedState.isEmpty, returnedState != session.state {
            setError("OAuth state mismatch. Please try signing in again.", for: provider)
            cancelInAppOAuthLogin()
            return
        }

        isCompletingOAuthLogin = true
        setError(nil, for: provider)

        Task {
            do {
                try await UsageService.completeOAuthAuthorization(
                    provider: provider,
                    code: code,
                    state: session.state,
                    codeVerifier: session.codeVerifier
                )
                self.setServiceError(nil, for: provider)
                self.cancelInAppOAuthLogin()
                self.refresh()
            } catch {
                self.setServiceError(error as? UsageServiceError, for: provider)
                self.setError(error.localizedDescription, for: provider)
                self.cancelInAppOAuthLogin()
            }
        }
    }

    func handleInAppOAuthFailure(_ message: String) {
        if let provider = loginProvider {
            setError(message, for: provider)
        }
        cancelInAppOAuthLogin()
    }

    private func setError(_ message: String?, for provider: UsageProvider) {
        switch provider {
        case .claude: claudeError = message
        case .codex: codexError = message
        }
    }

    private func setServiceError(_ error: UsageServiceError?, for provider: UsageProvider) {
        switch provider {
        case .claude: claudeServiceError = error
        case .codex: codexServiceError = error
        }
    }

    private func scheduleResetRefresh() {
        resetTimer?.invalidate()
        resetTimer = nil

        let now = Date()
        let resetDates = [claudeUsage, codexUsage]
            .compactMap { $0 }
            .flatMap { [$0.fiveHour.resetDate, $0.sevenDay.resetDate] }
            .compactMap { $0 }
            .filter { $0 > now }

        guard let earliest = resetDates.min() else { return }

        let delay = earliest.timeIntervalSince(now) + 2
        resetTimer = Timer.scheduledTimer(
            withTimeInterval: delay,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
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
