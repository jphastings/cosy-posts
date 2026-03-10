import SwiftUI
import os

private let log = Logger(subsystem: "com.cosyposts", category: "AccessRequests")

@Observable
@MainActor
final class AccessRequestsLoader {
    var emails: [String] = []
    var isLoading = false
    var error: String?

    private func makeRequest(serverURL: URL, path: String, method: String = "GET", token: String?) -> URLRequest {
        let encoded = path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path
        let url = serverURL.appendingPathComponent(encoded)
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    func load(serverURL: URL, token: String?) async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        let request = makeRequest(serverURL: serverURL, path: "api/access-requests", token: token)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return }
            if http.statusCode == 401 {
                NotificationCenter.default.post(name: .authSessionExpired, object: nil)
                return
            }
            guard http.statusCode == 200 else {
                error = "HTTP \(http.statusCode)"
                return
            }
            emails = try JSONDecoder().decode([String].self, from: data)
        } catch {
            self.error = error.localizedDescription
            log.error("Failed to load access requests: \(error)")
        }
    }

    func approve(email: String, serverURL: URL, token: String?) async -> Bool {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        let request = makeRequest(
            serverURL: serverURL,
            path: "api/access-requests/\(encodedEmail)/approve",
            method: "POST",
            token: token
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            emails.removeAll { $0 == email }
            return true
        } catch {
            log.error("Failed to approve \(email): \(error)")
            return false
        }
    }

    func deny(email: String, serverURL: URL, token: String?) async -> Bool {
        let encodedEmail = email.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? email
        let request = makeRequest(
            serverURL: serverURL,
            path: "api/access-requests/\(encodedEmail)",
            method: "DELETE",
            token: token
        )

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
            emails.removeAll { $0 == email }
            return true
        } catch {
            log.error("Failed to deny \(email): \(error)")
            return false
        }
    }
}

struct AccessRequestsView: View {
    let authManager: AuthManager
    var loader: AccessRequestsLoader

    var body: some View {
        if !loader.emails.isEmpty {
            Section {
                ForEach(loader.emails, id: \.self) { email in
                    AccessRequestRow(
                        email: email,
                        onApprove: {
                            guard let url = authManager.serverURL else { return false }
                            return await loader.approve(email: email, serverURL: url, token: authManager.sessionToken)
                        },
                        onDeny: {
                            guard let url = authManager.serverURL else { return false }
                            return await loader.deny(email: email, serverURL: url, token: authManager.sessionToken)
                        }
                    )
                }
            } header: {
                HStack {
                    Text("Access Requests")
                    Spacer()
                    Text("\(loader.emails.count)")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.red, in: .capsule)
                }
            }
        }
    }
}

private struct AccessRequestRow: View {
    let email: String
    let onApprove: () async -> Bool
    let onDeny: () async -> Bool
    @State private var isProcessing = false
    @State private var failed = false

    var body: some View {
        HStack {
            Text(email)
                .font(.subheadline)
                .lineLimit(1)

            Spacer()

            if isProcessing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Button {
                    Task {
                        isProcessing = true
                        failed = false
                        let ok = await onApprove()
                        isProcessing = false
                        if !ok { failed = true }
                    }
                } label: {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                }
                .buttonStyle(.plain)

                Button {
                    Task {
                        isProcessing = true
                        failed = false
                        let ok = await onDeny()
                        isProcessing = false
                        if !ok { failed = true }
                    }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)

                if failed {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                }
            }
        }
    }
}
