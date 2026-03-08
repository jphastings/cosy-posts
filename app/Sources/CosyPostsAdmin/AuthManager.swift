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

    /// Whether a magic link has been sent and we're waiting for the user to tap it.
    var awaitingMagicLink: Bool = false

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

        guard serverURL != nil else { return }
        _ = await verifyToken(token)
    }

    /// Exchange a magic link token for a session. Returns true on success.
    @discardableResult
    func verifyToken(_ token: String) async -> Bool {
        guard let serverURL else { return false }

        let verifyURL = serverURL.appendingPathComponent("auth/verify")
        var urlComponents = URLComponents(url: verifyURL, resolvingAgainstBaseURL: false)!
        urlComponents.queryItems = [URLQueryItem(name: "token", value: token)]

        var request = URLRequest(url: urlComponents.url!)
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                return false
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
            return true
        } catch {
            return false
        }
    }

    /// Send a magic link email via the server's POST /auth/send endpoint.
    func sendMagicLink(email: String) async {
        guard let serverURL else { return }
        loginError = nil

        let sendURL = serverURL.appendingPathComponent("auth/send")
        var request = URLRequest(url: sendURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var components = URLComponents()
        components.queryItems = [URLQueryItem(name: "email", value: email)]
        request.httpBody = components.percentEncodedQuery?.data(using: .utf8)

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                loginError = "Invalid response from server."
                return
            }
            if httpResponse.statusCode == 200 {
                awaitingMagicLink = true
            } else if httpResponse.statusCode == 403 {
                loginError = "This email is not authorized to post."
            } else {
                loginError = "Server error (HTTP \(httpResponse.statusCode))."
            }
        } catch {
            loginError = "Could not connect to the server."
        }
    }

    func logout() {
        sessionToken = nil
    }
}
