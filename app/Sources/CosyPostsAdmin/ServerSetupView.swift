import SwiftUI

/// Collects server URL and email, sends a magic link, and waits for the user to tap it.
struct ServerSetupView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var urlText = ""
    @State private var emailText = ""
    @State private var isSending = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Cosy Posts")
                .font(.title2.weight(.semibold))
                .tracking(-0.5)

            if authManager.awaitingMagicLink {
                // Waiting for the user to tap the magic link in their email.
                Image(systemName: "envelope.open")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("Check your email for a login link.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Send again") {
                    Task {
                        isSending = true
                        await authManager.sendMagicLink(email: emailText)
                        isSending = false
                    }
                }
                .disabled(isSending)

                Button("Use a different email") {
                    authManager.awaitingMagicLink = false
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            } else {
                Text("Enter your server address and email to log in.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 12) {
                    TextField("https://example.org", text: $urlText)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif

                    TextField("you@example.com", text: $emailText)
                        .textFieldStyle(.roundedBorder)
                        .textContentType(.emailAddress)
                        .autocorrectionDisabled()
                        #if !os(macOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.emailAddress)
                        #endif
                }
                .padding(.horizontal)

                if let error = authManager.loginError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }

                Button("Send Login Link") {
                    var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
                        text = "https://" + text
                    }
                    if let url = URL(string: text) {
                        authManager.serverURL = url
                        Task {
                            isSending = true
                            await authManager.sendMagicLink(email: emailText.trimmingCharacters(in: .whitespacesAndNewlines))
                            isSending = false
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    emailText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    isSending
                )
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Pre-fill from saved values.
            if let url = authManager.serverURL {
                urlText = url.absoluteString
            }
            if let email = authManager.email {
                emailText = email
            }
        }
    }
}
