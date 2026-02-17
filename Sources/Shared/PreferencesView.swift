import SwiftUI

struct PreferencesView: View {
    var menuBarShowsBoth: Binding<Bool>?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
#if os(macOS)
        Form {
            content
        }
        .formStyle(.grouped)
        .frame(minWidth: 320, minHeight: 200)
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
    }
}
