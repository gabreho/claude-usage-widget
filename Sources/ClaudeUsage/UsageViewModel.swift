import Foundation
import SwiftUI
import ClaudeUsageKit

@MainActor
final class UsageViewModel: ObservableObject {
    enum MenuBarLabelMode: String {
        case both
        case highest
    }

    private static let menuBarLabelModeDefaultsKey = "menuBarLabelMode"

    @Published var usage: UsageResponse?
    @Published var error: String?
    @Published var isLoading = false
    @Published var isCompletingOAuthLogin = false
    @Published var lastUpdated: Date?
    @Published var oauthAuthorizationURL: URL?
    @Published var isShowingOAuthLogin = false
    @Published var menuBarLabelMode: MenuBarLabelMode {
        didSet {
            UserDefaults.standard.set(
                menuBarLabelMode.rawValue,
                forKey: Self.menuBarLabelModeDefaultsKey
            )
        }
    }

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 300
    private var lastServiceError: UsageServiceError?
    private var oauthAuthorizationSession: UsageService.OAuthAuthorizationSession?

    init() {
        let storedModeRawValue = UserDefaults.standard.string(
            forKey: Self.menuBarLabelModeDefaultsKey
        )
        self.menuBarLabelMode = MenuBarLabelMode(rawValue: storedModeRawValue ?? "") ?? .both
        NSApplication.shared.setActivationPolicy(.accessory)
        startAutoRefresh()
    }

    var primaryUtilization: Double {
        guard let usage else { return 0 }
        guard hasFutureResetDate(for: usage.fiveHour) else {
            return usage.sevenDay.utilization
        }
        return max(usage.fiveHour.utilization, usage.sevenDay.utilization)
    }

    var primaryTier: UsageTier {
        switch primaryUtilization {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    var menuBarLabel: String {
        guard let usage else { return "—" }

        switch menuBarLabelMode {
        case .both:
            let fiveHourLabelValue: String
            if hasFutureResetDate(for: usage.fiveHour) {
                fiveHourLabelValue = "\(Int(usage.fiveHour.utilization))%"
            } else {
                fiveHourLabelValue = "--"
            }
            let sevenDayPercent = Int(usage.sevenDay.utilization)
            return "5h:\(fiveHourLabelValue) 7d:\(sevenDayPercent)%"
        case .highest:
            return "\(Int(primaryUtilization))%"
        }
    }

    var menuBarIcon: String {
        switch primaryTier {
        case .green: return "gauge.with.dots.needle.0percent"
        case .yellow: return "gauge.with.dots.needle.50percent"
        case .red: return "gauge.with.dots.needle.100percent"
        }
    }

    var shouldOfferInAppLogin: Bool {
        lastServiceError?.supportsInAppLoginRecovery == true
    }

    func startAutoRefresh() {
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

    func stopAutoRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func refresh() {
        guard !isLoading, !isCompletingOAuthLogin else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await UsageService.fetchUsage()
                self.usage = result
                self.lastUpdated = Date()
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

    private func hasFutureResetDate(for limit: UsageLimit) -> Bool {
        guard let resetDate = limit.resetDate else {
            return false
        }
        return resetDate > Date()
    }
}
