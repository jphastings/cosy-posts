import Foundation
import SwiftUI

extension Notification.Name {
    /// Posted by any component that receives an HTTP 401, indicating the session is invalid.
    static let authSessionExpired = Notification.Name("authSessionExpired")
}

/// Manages authentication state: server URL, session token, and deep link handling.
@Observable
@MainActor
final class AuthManager {
    var serverURL: URL? {
        didSet {
            if let url = serverURL {
                UserDefaults.standard.set(url.absoluteString, forKey: "serverURL")
            } else {
                UserDefaults.standard.removeObject(forKey: "serverURL")
            }
        }
    }

    var sessionToken: String? {
        didSet {
            if let token = sessionToken {
                UserDefaults.standard.set(token, forKey: "sessionToken")
            } else {
                UserDefaults.standard.removeObject(forKey: "sessionToken")
            }
        }
    }

    var email: String? {
        didSet {
            if let email {
                UserDefaults.standard.set(email, forKey: "userEmail")
            } else {
                UserDefaults.standard.removeObject(forKey: "userEmail")
            }
        }
    }

    /// Error message to display on the login screen (e.g. expired/used token).
    var loginError: String?

    var isAuthenticated: Bool { sessionToken != nil }
    var isServerConfigured: Bool { serverURL != nil }

    init() {
        if let urlString = UserDefaults.standard.string(forKey: "serverURL") {
            self.serverURL = URL(string: urlString)
        }
        self.sessionToken = UserDefaults.standard.string(forKey: "sessionToken")
        self.email = UserDefaults.standard.string(forKey: "userEmail")
    }

    /// Handle a cosy:// deep link.
    /// Expected format: cosy://auth?token={token}&server={serverURL}
    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "cosy", url.host == "auth" else { return }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        guard let token = components?.queryItems?.first(where: { $0.name == "token" })?.value else {
            return
        }

        // Optionally update server URL from the deep link.
        if let serverString = components?.queryItems?.first(where: { $0.name == "server" })?.value,
           let url = URL(string: serverString) {
            self.serverURL = url
        }

        guard let serverURL else { return }

        // Exchange the token for a session by calling /auth/verify on the server.
        let verifyURL = serverURL.appendingPathComponent("auth/verify")
        var urlComponents = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                self.loginError = "This login link has already been used. Please request a new one."
                return
            }

            struct VerifyResponse: Decodable {
                let session: String
                let role: String
                let email: String
            }

            let result = try JSONDecoder().decode(VerifyResponse.self, from: data)
            self.loginError = nil
            self.sessionToken = result.session
            self.email = result.email
        } catch {
            self.loginError = "Could not connect to the server. Please try again."
        }
    }

    func logout() {
        sessionToken = nil
    }
}
