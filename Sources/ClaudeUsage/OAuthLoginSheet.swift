import ClaudeUsageKit
import SwiftUI
import WebKit

struct OAuthLoginSheet: View {
    let authorizationURL: URL
    let isCompletingLogin: Bool
    let onCancel: () -> Void
    let onCodeReceived: (_ code: String, _ state: String?) -> Void
    let onFailure: (_ message: String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Sign in to Claude")
                    .font(.headline)
                Spacer()
                if isCompletingLogin {
                    ProgressView()
                        .controlSize(.small)
                }
                Button("Cancel", action: onCancel)
                    .buttonStyle(.borderless)
            }
            .padding()

            Divider()

            OAuthWebView(
                initialURL: authorizationURL,
                callbackURL: UsageService.oauthRedirectURL,
                onCodeReceived: onCodeReceived,
                onFailure: onFailure
            )
        }
        .frame(minWidth: 760, minHeight: 560)
    }
}

private struct OAuthWebView: NSViewRepresentable {
    let initialURL: URL
    let callbackURL: URL
    let onCodeReceived: (_ code: String, _ state: String?) -> Void
    let onFailure: (_ message: String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            callbackURL: callbackURL,
            onCodeReceived: onCodeReceived,
            onFailure: onFailure
        )
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()

        let preferences = WKPreferences()
        preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences = preferences

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        var request = URLRequest(url: initialURL)
        request.timeoutInterval = 30
        webView.load(request)

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.updateHandlers(
            callbackURL: callbackURL,
            onCodeReceived: onCodeReceived,
            onFailure: onFailure
        )

        if webView.url == nil {
            var request = URLRequest(url: initialURL)
            request.timeoutInterval = 30
            webView.load(request)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        private var callbackURL: URL
        private var onCodeReceived: (_ code: String, _ state: String?) -> Void
        private var onFailure: (_ message: String) -> Void
        private var didReportResult = false

        init(
            callbackURL: URL,
            onCodeReceived: @escaping (_ code: String, _ state: String?) -> Void,
            onFailure: @escaping (_ message: String) -> Void
        ) {
            self.callbackURL = callbackURL
            self.onCodeReceived = onCodeReceived
            self.onFailure = onFailure
        }

        func updateHandlers(
            callbackURL: URL,
            onCodeReceived: @escaping (_ code: String, _ state: String?) -> Void,
            onFailure: @escaping (_ message: String) -> Void
        ) {
            self.callbackURL = callbackURL
            self.onCodeReceived = onCodeReceived
            self.onFailure = onFailure
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if isOAuthCallback(url),
               let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
               let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
               !code.isEmpty {
                let state = components.queryItems?.first(where: { $0.name == "state" })?.value
                reportSuccess(code: code, state: state)
                decisionHandler(.cancel)
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didReportResult,
                  let currentURL = webView.url,
                  isOAuthCallback(currentURL) else {
                return
            }

            let script = """
            (() => {
              const params = new URLSearchParams(window.location.search);
              const queryCode = params.get("code");
              const queryState = params.get("state");
              if (queryCode) {
                return { code: queryCode, state: queryState || "" };
              }

              const bodyText = document.body && document.body.innerText ? document.body.innerText : "";
              const codeElement = document.querySelector("code");
              const codeElementText = codeElement && codeElement.textContent ? codeElement.textContent.trim() : "";
              const match = bodyText.match(/(?:^|\\s)code\\s*[:=]\\s*([A-Za-z0-9._-]+)/i);
              const inferredCode = codeElementText || (match ? match[1] : "");

              return { code: inferredCode, state: queryState || "" };
            })()
            """

            webView.evaluateJavaScript(script) { [weak self] result, error in
                guard let self else {
                    return
                }

                if let error {
                    self.reportFailure("OAuth callback parsing failed: \(error.localizedDescription)")
                    return
                }

                guard let payload = result as? [String: Any],
                      let code = payload["code"] as? String else {
                    self.reportFailure("OAuth callback loaded, but no authorization code was found.")
                    return
                }

                let trimmedCode = code.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmedCode.isEmpty else {
                    self.reportFailure("OAuth callback loaded, but no authorization code was found.")
                    return
                }

                let stateValue = (payload["state"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                self.reportSuccess(code: trimmedCode, state: stateValue)
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            if shouldIgnoreNavigationError(error) {
                return
            }
            reportFailure("Login page failed to load: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            if shouldIgnoreNavigationError(error) {
                return
            }
            reportFailure("Login page failed to load: \(error.localizedDescription)")
        }

        func webView(
            _ webView: WKWebView,
            createWebViewWith configuration: WKWebViewConfiguration,
            for navigationAction: WKNavigationAction,
            windowFeatures: WKWindowFeatures
        ) -> WKWebView? {
            if navigationAction.targetFrame == nil {
                webView.load(navigationAction.request)
            }
            return nil
        }

        private func shouldIgnoreNavigationError(_ error: Error) -> Bool {
            let nsError = error as NSError
            return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
        }

        private func isOAuthCallback(_ url: URL) -> Bool {
            url.scheme?.lowercased() == callbackURL.scheme?.lowercased()
                && url.host?.lowercased() == callbackURL.host?.lowercased()
                && url.path == callbackURL.path
        }

        private func reportSuccess(code: String, state: String?) {
            guard !didReportResult else {
                return
            }
            didReportResult = true
            onCodeReceived(code, state)
        }

        private func reportFailure(_ message: String) {
            guard !didReportResult else {
                return
            }
            didReportResult = true
            onFailure(message)
        }
    }
}
