import ClaudeUsageKit
import SwiftUI

struct PreferencesView: View {
    var menuBarShowsBoth: Binding<Bool>?
    var onSignOut: ((UsageProvider) -> Void)?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
#if os(macOS)
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(width: 320)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
#elseif os(iOS)
        NavigationStack {
            Form {
                content
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
#endif
    }

    private var authenticatedProviders: [UsageProvider] {
        UsageProvider.allCases.filter { UsageService.isAuthenticated(provider: $0) }
    }

    @ViewBuilder
    private var content: some View {
        if let menuBarShowsBoth {
            Section("Menu Bar") {
                Toggle("Show both providers in menu bar", isOn: menuBarShowsBoth)
            }
        }

        let providers = authenticatedProviders
        if !providers.isEmpty {
            Section("Accounts") {
                ForEach(providers, id: \.self) { provider in
                    Button("Sign Out of \(provider.displayName)", role: .destructive) {
                        UsageService.signOut(provider: provider)
                        onSignOut?(provider)
                    }
                }
            }
        }
    }
}
