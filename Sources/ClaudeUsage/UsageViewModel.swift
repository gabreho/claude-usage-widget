import Foundation
import SwiftUI

@MainActor
final class UsageViewModel: ObservableObject {
    @Published var usage: UsageResponse?
    @Published var error: String?
    @Published var isLoading = false
    @Published var lastUpdated: Date?

    private var refreshTimer: Timer?
    private let refreshInterval: TimeInterval = 300

    var primaryUtilization: Double {
        guard let usage else { return 0 }
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
        guard usage != nil else { return "—" }
        return "\(Int(primaryUtilization))%"
    }

    var menuBarIcon: String {
        switch primaryTier {
        case .green: return "gauge.with.dots.needle.0percent"
        case .yellow: return "gauge.with.dots.needle.50percent"
        case .red: return "gauge.with.dots.needle.100percent"
        }
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
        guard !isLoading else { return }
        isLoading = true
        error = nil

        Task {
            do {
                let result = try await UsageService.fetchUsage()
                self.usage = result
                self.lastUpdated = Date()
                self.error = nil
            } catch {
                self.error = error.localizedDescription
            }
            self.isLoading = false
        }
    }
}
