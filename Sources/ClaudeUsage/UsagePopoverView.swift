import SwiftUI
import ClaudeUsageKit

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openSettings) private var openSettings
    @State private var codeInput = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isShowingCodeEntry {
                inlineCodeEntryForm
            } else {
                UsageDashboardView(
                    style: .popover,
                    usage: viewModel.usage,
                    errorMessage: viewModel.error,
                    isLoading: viewModel.isLoading,
                    shouldOfferInAppLogin: viewModel.shouldOfferInAppLogin,
                    lastUpdated: viewModel.lastUpdated,
                    onLogin: { viewModel.startInAppOAuthLogin() },
                    headerAccessory: {
                        Button(action: {
                            openSettings()
                            NSApp.activate(ignoringOtherApps: true)
                        }) {
                            Image(systemName: "gearshape")
                        }
                        .buttonStyle(.borderless)
                        Button(action: { viewModel.refresh() }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.isLoading || viewModel.isCompletingOAuthLogin)
                    },
                    footerAccessory: {
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .buttonStyle(.borderless)
                        .font(.caption)
                    }
                )
            }
        }
        .padding()
        .frame(width: 280)
        .onChange(of: viewModel.isShowingCodeEntry) { _, showing in
            if !showing { codeInput = "" }
        }
    }

    private var inlineCodeEntryForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sign in to Claude")
                .font(.headline)
            Text("Complete sign-in in your browser, then paste the code shown on the page below.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Paste authentication code", text: $codeInput)
                .textFieldStyle(.roundedBorder)
            if viewModel.isCompletingOAuthLogin {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Signing in…").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel") {
                    viewModel.cancelInAppOAuthLogin()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Continue") {
                    viewModel.submitOAuthCode(codeInput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || viewModel.isCompletingOAuthLogin)
            }
        }
    }

}
