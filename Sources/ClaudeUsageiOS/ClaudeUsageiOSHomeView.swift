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
                    usage: viewModel.usage,
                    errorMessage: viewModel.error,
                    isLoading: viewModel.isLoading,
                    shouldOfferInAppLogin: viewModel.shouldOfferInAppLogin,
                    lastUpdated: viewModel.lastUpdated,
                    unavailableMessage: "No usage data yet. Pull to refresh or try again in a moment.",
                    onLogin: { viewModel.startInAppOAuthLogin() }
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
            PreferencesView(onSignOut: { viewModel.handleSignOut() })
        }
        .fullScreenCover(isPresented: $viewModel.isShowingOAuthLogin) {
            if let authorizationURL = viewModel.oauthAuthorizationURL {
                OAuthLoginView(
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
    @Published var usage: UsageResponse?
    @Published var error: String?
    @Published var isLoading = false
    @Published var isCompletingOAuthLogin = false
    @Published var lastUpdated: Date?
    @Published var oauthAuthorizationURL: URL?
    @Published var isShowingOAuthLogin = false

    private let refreshInterval: TimeInterval = 300
    private var refreshTimer: Timer?
    private var resetTimer: Timer?
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
                self.scheduleResetRefresh()
            } catch {
                self.lastServiceError = error as? UsageServiceError
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }

    func handleSignOut() {
        usage = nil
        lastUpdated = nil
        error = nil
        lastServiceError = nil
        refresh()
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

    private func scheduleResetRefresh() {
        resetTimer?.invalidate()
        resetTimer = nil

        guard let usage else { return }

        let now = Date()
        let resetDates = [usage.fiveHour.resetDate, usage.sevenDay.resetDate].compactMap { $0 }
        guard let earliest = resetDates.filter({ $0 > now }).min() else { return }

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
