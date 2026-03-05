import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// Shows the server's login page in a web view.
/// The user enters their email, receives a magic link, and taps the app link
/// which triggers a chaos:// deep link handled by the app.
struct LoginView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        VStack(spacing: 0) {
            if let serverURL = authManager.serverURL {
                let loginURL = serverURL.appendingPathComponent("auth/login")
                #if canImport(UIKit)
                WebView(url: loginURL)
                    .ignoresSafeArea(edges: .bottom)
                #else
                // macOS: open in default browser
                VStack(spacing: 24) {
                    Spacer()
                    Text("Check your browser to log in.")
                        .font(.headline)
                    Link("Open Login Page", destination: loginURL)
                        .buttonStyle(.borderedProminent)
                    Spacer()
                }
                .onAppear {
                    NSWorkspace.shared.open(loginURL)
                }
                #endif
            }
        }
    }
}

#if canImport(UIKit)
/// A minimal WKWebView wrapper for SwiftUI.
struct WebView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.load(URLRequest(url: url))
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}
}
#endif
