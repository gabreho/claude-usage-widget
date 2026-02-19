import ClaudeUsageKit
import SwiftUI

struct PreferencesView: View {
    var menuBarShowsBoth: Binding<Bool>?
    var onSignOut: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @State private var isAuthenticated = UsageService.isAuthenticated

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

    @ViewBuilder
    private var content: some View {
        if let menuBarShowsBoth {
            Section("Menu Bar") {
                Toggle("Show 5h and 7d in menu bar", isOn: menuBarShowsBoth)
            }
        }

        if isAuthenticated {
            Section("Account") {
                Button("Sign Out", role: .destructive) {
                    UsageService.signOut()
                    dismiss()
                    onSignOut?()
                }
            }
        }
    }
}
