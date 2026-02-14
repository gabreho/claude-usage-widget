import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(viewModel: viewModel)
                .task {
                    NSApplication.shared.setActivationPolicy(.accessory)
                    viewModel.startAutoRefresh()
                }
        } label: {
            HStack(spacing: 2) {
                Image(systemName: viewModel.menuBarIcon)
                Text(viewModel.menuBarLabel)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)
    }
}
