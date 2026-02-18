import SwiftUI

@main
struct ClaudeUsageApp: App {
    @StateObject private var viewModel = UsageViewModel()

    var body: some Scene {
        MenuBarExtra {
            UsagePopoverView(viewModel: viewModel)
        } label: {
            HStack(spacing: 2) {
                Image(systemName: viewModel.menuBarIcon)
                Text(viewModel.menuBarLabel)
                    .monospacedDigit()
            }
        }
        .menuBarExtraStyle(.window)

        Settings {
            PreferencesView(menuBarShowsBoth: menuBarShowsBothBinding)
        }
    }

    private var menuBarShowsBothBinding: Binding<Bool> {
        Binding(
            get: { viewModel.menuBarLabelMode == .both },
            set: { viewModel.menuBarLabelMode = $0 ? .both : .highest }
        )
    }
}
