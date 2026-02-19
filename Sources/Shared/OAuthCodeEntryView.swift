import SwiftUI

struct OAuthCodeEntryView: View {
    let isCompletingLogin: Bool
    let onSubmit: (_ code: String) -> Void
    let onCancel: () -> Void

    @State private var code = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("A browser window has opened for you to sign in to Claude. Once you're signed in, copy the authentication code from the browser and paste it below.")
                    .foregroundStyle(.secondary)

                TextField("Paste authentication code", text: $code)
                    .textFieldStyle(.roundedBorder)
#if os(iOS)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
#endif

                if isCompletingLogin {
                    HStack {
                        ProgressView()
                        Text("Signing in…")
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Enter Code")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Continue") {
                        onSubmit(code.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    .disabled(code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCompletingLogin)
                }
            }
        }
#if os(macOS)
        .frame(width: 400, height: 200)
#endif
    }
}
