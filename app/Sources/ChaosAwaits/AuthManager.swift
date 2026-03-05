import Foundation
import SwiftUI

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

    var isAuthenticated: Bool { sessionToken != nil }
    var isServerConfigured: Bool { serverURL != nil }

    init() {
        if let urlString = UserDefaults.standard.string(forKey: "serverURL") {
            self.serverURL = URL(string: urlString)
        }
        self.sessionToken = UserDefaults.standard.string(forKey: "sessionToken")
    }

    /// Handle a chaos:// deep link.
    /// Expected format: chaos://auth?token={token}&server={serverURL}
    func handleDeepLink(_ url: URL) async {
        guard url.scheme == "chaos", url.host == "auth" else { return }

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
                return
            }

            struct VerifyResponse: Decodable {
                let session: String
                let role: String
            }

            let result = try JSONDecoder().decode(VerifyResponse.self, from: data)
            self.sessionToken = result.session
        } catch {
            // Token exchange failed; user will need to log in again.
        }
    }

    func logout() {
        sessionToken = nil
    }
}
