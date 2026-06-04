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
                    title: "Usage",
                    sections: viewModel.sections,
                    isLoading: viewModel.isLoading,
                    lastUpdated: viewModel.lastUpdated,
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
                        .disabled(viewModel.isLoading || viewModel.isCompletingClaudeLogin || viewModel.isCompletingCodexLogin)
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
        .sheet(isPresented: $viewModel.isShowingCodexWebLogin) {
            if let authorizationURL = viewModel.codexAuthorizationURL {
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
            if viewModel.isCompletingClaudeLogin {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Signing in…").foregroundStyle(.secondary)
                }
            }
            HStack {
                Button("Cancel") {
                    viewModel.cancelClaudeLogin()
                }
                .buttonStyle(.borderless)
                Spacer()
                Button("Continue") {
                    viewModel.submitOAuthCode(codeInput.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .disabled(codeInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                          || viewModel.isCompletingClaudeLogin)
            }
        }
    }

}
