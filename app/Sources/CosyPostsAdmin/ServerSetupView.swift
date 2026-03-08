import SwiftUI

/// Collects server URL and email, sends a magic link, and waits for the user to tap it.
struct ServerSetupView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var urlText = ""
    @State private var emailText = ""
    @State private var isSending = false
    @State private var showingTokenEntry = false

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

                Button("Enter token") {
                    showingTokenEntry = true
                }
                .font(.caption)

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
        .sheet(isPresented: $showingTokenEntry) {
            TokenEntrySheet(authManager: authManager)
        }
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

/// Sheet for manually entering a magic link token.
struct TokenEntrySheet: View {
    var authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var tokenText = ""
    @State private var shakeCount = 0
    @State private var isVerifying = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Paste the token from your login email.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField("Token", text: $tokenText)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    #endif
                    .modifier(ShakeModifier(shakeCount: shakeCount))

                Button("Save") {
                    let token = tokenText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !token.isEmpty else { return }
                    isVerifying = true
                    Task {
                        let success = await authManager.verifyToken(token)
                        isVerifying = false
                        if success {
                            dismiss()
                        } else {
                            tokenText = ""
                            withAnimation(.default) {
                                shakeCount += 1
                            }
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(tokenText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isVerifying)

                Spacer()
            }
            .padding()
            .navigationTitle("Enter Token")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// Applies a horizontal shake animation, driven by incrementing `shakeCount`.
struct ShakeEffect: GeometryEffect {
    var shakeCount: CGFloat

    var animatableData: CGFloat {
        get { shakeCount }
        set { shakeCount = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: sin(shakeCount * .pi * 4) * 8, y: 0))
    }
}

struct ShakeModifier: ViewModifier {
    var shakeCount: Int

    func body(content: Content) -> some View {
        content.modifier(ShakeEffect(shakeCount: CGFloat(shakeCount)))
    }
}
