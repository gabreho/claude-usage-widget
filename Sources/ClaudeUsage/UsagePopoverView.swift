import SwiftUI
import ClaudeUsageKit

struct UsagePopoverView: View {
    @ObservedObject var viewModel: UsageViewModel
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            UsageDashboardView(
                style: .popover,
                usage: viewModel.usage,
                errorMessage: viewModel.error,
                isLoading: viewModel.isLoading,
                shouldOfferInAppLogin: viewModel.shouldOfferInAppLogin,
                lastUpdated: viewModel.lastUpdated,
                onLogin: { viewModel.startInAppOAuthLogin() },
                headerAccessory: {
                    Button(action: { openSettings() }) {
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
        .padding()
        .frame(width: 280)
        .sheet(isPresented: $viewModel.isShowingOAuthLogin) {
            if let authorizationURL = viewModel.oauthAuthorizationURL {
                OAuthLoginView(
                    authorizationURL: authorizationURL,
                    isCompletingLogin: viewModel.isCompletingOAuthLogin,
                    onCancel: { viewModel.cancelInAppOAuthLogin() },
                    onCodeReceived: { code, state in
                        viewModel.completeInAppOAuthLogin(code: code, returnedState: state)
                    },
                    onFailure: { message in
                        viewModel.handleInAppOAuthFailure(message)
                    }
                )
            }
        }
    }

}
