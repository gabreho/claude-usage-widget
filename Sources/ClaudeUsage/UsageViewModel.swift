import Foundation
import SwiftUI
import ClaudeUsageKit
import WidgetKit

@MainActor
final class UsageViewModel: ObservableObject {
    enum MenuBarLabelMode: String {
        case both
        case highest
    }

    private static let menuBarLabelModeDefaultsKey = "menuBarLabelMode"

    // Per-provider usage + error state.
    @Published var claudeUsage: UsageResponse?
    @Published var codexUsage: UsageResponse?
    @Published var claudeError: String?
    @Published var codexError: String?

    @Published var isLoading = false
    @Published var lastUpdated: Date?

    // Claude sign-in (system browser + paste code).
    @Published var isShowingCodeEntry = false
    @Published var isCompletingClaudeLogin = false

    // Codex sign-in (embedded web view captures the loopback redirect).
    @Published var isCompletingCodexLogin = false

    @Published var menuBarLabelMode: MenuBarLabelMode {
        didSet {
            UserDefaults.standard.set(
                menuBarLabelMode.rawValue,
                forKey: Self.menuBarLabelModeDefaultsKey
            )
        }
    }

    private var refreshTimer: Timer?
    private var resetTimer: Timer?
    private let refreshInterval: TimeInterval = 300

    private var claudeServiceError: UsageServiceError?
    private var codexServiceError: UsageServiceError?
    private var claudeOAuthSession: UsageService.OAuthAuthorizationSession?
    private var codexOAuthSession: UsageService.OAuthAuthorizationSession?
    private var codexLoginWindowController: OAuthLoginWindowController?

    init() {
        let storedModeRawValue = UserDefaults.standard.string(
            forKey: Self.menuBarLabelModeDefaultsKey
        )
        self.menuBarLabelMode = MenuBarLabelMode(rawValue: storedModeRawValue ?? "") ?? .both
        NSApplication.shared.setActivationPolicy(.accessory)
        startAutoRefresh()
    }

    // MARK: - Dashboard sections

    var sections: [ProviderUsageSection] {
        [
            ProviderUsageSection(
                provider: .claude,
                usage: claudeUsage,
                errorMessage: claudeError,
                shouldOfferInAppLogin: claudeServiceError?.supportsInAppLoginRecovery == true,
                onLogin: { [weak self] in self?.startClaudeLogin() }
            ),
            ProviderUsageSection(
                provider: .codex,
                usage: codexUsage,
                errorMessage: codexError,
                shouldOfferInAppLogin: codexServiceError?.supportsInAppLoginRecovery == true,
                onLogin: { [weak self] in self?.startCodexLogin() }
            )
        ]
    }

    // MARK: - Menu bar

    /// Highest "live" utilization across every signed-in provider, used for the gauge tint.
    private var primaryUtilization: Double {
        [claudeUsage, codexUsage]
            .compactMap { $0.map(highlightUtilization) }
            .max() ?? 0
    }

    private func highlightUtilization(_ usage: UsageResponse) -> Double {
        guard hasFutureResetDate(for: usage.fiveHour) else {
            return usage.sevenDay.utilization
        }
        return max(usage.fiveHour.utilization, usage.sevenDay.utilization)
    }

    private var primaryTier: UsageTier {
        switch primaryUtilization {
        case ..<50: return .green
        case ..<80: return .yellow
        default: return .red
        }
    }

    var menuBarLabel: String {
        let entries: [(UsageProvider, UsageResponse)] = [
            (.claude, claudeUsage),
            (.codex, codexUsage)
        ].compactMap { provider, usage in usage.map { (provider, $0) } }

        guard !entries.isEmpty else { return "—" }

        switch menuBarLabelMode {
        case .both:
            return entries
                .map { "\($0.0.menuBarPrefix):\(Int(highlightUtilization($0.1)))%" }
                .joined(separator: " ")
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

    // MARK: - Refresh

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
        resetTimer?.invalidate()
        resetTimer = nil
    }

    func refresh() {
        guard !isLoading, !isCompletingClaudeLogin, !isCompletingCodexLogin else { return }
        isLoading = true

        Task {
            async let claude: Void = fetch(.claude)
            async let codex: Void = fetch(.codex)
            _ = await (claude, codex)

            self.lastUpdated = Date()
            if self.claudeUsage != nil || self.codexUsage != nil {
                UsageWidgetSharedStore.save(
                    usage: self.claudeUsage,
                    codexUsage: self.codexUsage,
                    fetchedAt: Date()
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
            let serviceError = error as? UsageServiceError
            apply(usage: usage(for: provider), error: error.localizedDescription, serviceError: serviceError, for: provider)
        }
    }

    private func usage(for provider: UsageProvider) -> UsageResponse? {
        provider == .claude ? claudeUsage : codexUsage
    }

    private func apply(usage: UsageResponse?, error: String?, serviceError: UsageServiceError?, for provider: UsageProvider) {
        switch provider {
        case .claude:
            claudeUsage = error == nil ? usage : claudeUsage
            claudeError = error
            claudeServiceError = serviceError
        case .codex:
            codexUsage = error == nil ? usage : codexUsage
            codexError = error
            codexServiceError = serviceError
        }
    }

    // MARK: - Sign out

    func signOut(provider: UsageProvider) {
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
        persistSnapshot()
        refresh()
    }

    private func persistSnapshot() {
        UsageWidgetSharedStore.save(usage: claudeUsage, codexUsage: codexUsage, fetchedAt: Date())
        WidgetCenter.shared.reloadTimelines(ofKind: UsageWidgetSharedStore.widgetKind)
    }

    // MARK: - Claude sign-in (paste code)

    func startClaudeLogin() {
        let session = UsageService.createOAuthAuthorizationSession(provider: .claude)
        claudeOAuthSession = session
        NSWorkspace.shared.open(session.authorizationURL)
        isShowingCodeEntry = true
        claudeError = nil
    }

    func cancelClaudeLogin() {
        isShowingCodeEntry = false
        claudeOAuthSession = nil
        isCompletingClaudeLogin = false
    }

    func submitOAuthCode(_ raw: String) {
        guard let session = claudeOAuthSession else {
            claudeError = "OAuth session expired. Please try signing in again."
            return
        }

        // The code page displays codes as "{code}#{state}" — extract just the code part.
        let parts = raw.split(separator: "#", maxSplits: 1)
        let code = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let returnedState = parts.count > 1 ? String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines) : nil

        guard !code.isEmpty else {
            claudeError = "Please enter a valid authentication code."
            return
        }

        if let expectedState = session.state,
           let returnedState,
           !returnedState.isEmpty,
           returnedState != expectedState {
            claudeError = "OAuth state mismatch. Please try signing in again."
            cancelClaudeLogin()
            return
        }

        isCompletingClaudeLogin = true
        claudeError = nil

        Task {
            do {
                try await UsageService.completeOAuthAuthorization(
                    provider: .claude,
                    code: code,
                    state: session.state,
                    codeVerifier: session.codeVerifier
                )
                self.claudeServiceError = nil
                self.cancelClaudeLogin()
                self.refresh()
            } catch {
                self.claudeServiceError = error as? UsageServiceError
                self.claudeError = error.localizedDescription
                self.cancelClaudeLogin()
            }
        }
    }

    // MARK: - Codex sign-in (embedded web view, loopback redirect)

    func startCodexLogin() {
        let session = UsageService.createOAuthAuthorizationSession(provider: .codex)
        codexOAuthSession = session
        codexError = nil
        showCodexLoginWindow(authorizationURL: session.authorizationURL)
    }

    func cancelCodexLogin() {
        codexOAuthSession = nil
        isCompletingCodexLogin = false
        dismissCodexLoginWindow()
    }

    func completeCodexLogin(code: String, returnedState: String?) {
        guard let session = codexOAuthSession else {
            codexError = "OAuth session expired. Please try signing in again."
            return
        }

        if let expectedState = session.state,
           let returnedState,
           !returnedState.isEmpty,
           returnedState != expectedState {
            codexError = "OAuth state mismatch. Please try signing in again."
            cancelCodexLogin()
            return
        }

        isCompletingCodexLogin = true
        codexError = nil

        Task {
            do {
                try await UsageService.completeOAuthAuthorization(
                    provider: .codex,
                    code: code,
                    state: session.state,
                    codeVerifier: session.codeVerifier
                )
                self.codexServiceError = nil
                self.cancelCodexLogin()
                self.refresh()
            } catch {
                self.codexServiceError = error as? UsageServiceError
                self.codexError = error.localizedDescription
                self.cancelCodexLogin()
            }
        }
    }

    func handleCodexLoginFailure(_ message: String) {
        codexError = message
        cancelCodexLogin()
    }

    private func showCodexLoginWindow(authorizationURL: URL) {
        codexLoginWindowController?.close()
        let controller = OAuthLoginWindowController(
            viewModel: self,
            authorizationURL: authorizationURL
        )
        codexLoginWindowController = controller
        controller.show()
    }

    private func dismissCodexLoginWindow() {
        codexLoginWindowController?.close()
        codexLoginWindowController = nil
    }

    // MARK: - Reset-driven refresh

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

    private func hasFutureResetDate(for limit: UsageLimit) -> Bool {
        guard let resetDate = limit.resetDate else {
            return false
        }
        return resetDate > Date()
    }
}

@MainActor
private final class OAuthLoginWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var isClosingProgrammatically = false
    private let onClose: () -> Void

    init(viewModel: UsageViewModel, authorizationURL: URL) {
        self.onClose = { [weak viewModel] in
            viewModel?.cancelCodexLogin()
        }

        let content = CodexOAuthLoginWindowContent(
            viewModel: viewModel,
            authorizationURL: authorizationURL
        )
        let hostingController = NSHostingController(rootView: content)
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "Sign in to Codex"
        window.setContentSize(NSSize(width: 760, height: 560))
        window.minSize = NSSize(width: 640, height: 480)
        window.isReleasedWhenClosed = false
        window.isFloatingPanel = true
        window.hidesOnDeactivate = false
        window.level = .floating
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        window.tabbingMode = .disallowed
        window.center()

        self.window = window
        super.init()
        window.delegate = self
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func close() {
        guard let window else {
            return
        }

        isClosingProgrammatically = true
        window.close()
        isClosingProgrammatically = false
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
        if !isClosingProgrammatically {
            onClose()
        }
    }
}

private struct CodexOAuthLoginWindowContent: View {
    @ObservedObject var viewModel: UsageViewModel
    let authorizationURL: URL

    var body: some View {
        OAuthLoginView(
            provider: .codex,
            authorizationURL: authorizationURL,
            isCompletingLogin: viewModel.isCompletingCodexLogin,
            onCancel: { viewModel.cancelCodexLogin() },
            onCodeReceived: { code, state in
                viewModel.completeCodexLogin(code: code, returnedState: state)
            },
            onFailure: { message in
                viewModel.handleCodexLoginFailure(message)
            }
        )
    }
}
