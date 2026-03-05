import SwiftUI

/// Shown when no server URL is configured. User enters the server address.
struct ServerSetupView: View {
    @Environment(AuthManager.self) private var authManager
    @State private var urlText = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("chaos.awaits.us")
                .font(.title2.weight(.semibold))
                .tracking(-0.5)

            Text("Enter your server address to get started.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            TextField("https://chaos.awaits.us", text: $urlText)
                .textFieldStyle(.roundedBorder)
                .textContentType(.URL)
                .autocorrectionDisabled()
                #if !os(macOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
                .padding(.horizontal)

            Button("Continue") {
                var text = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.hasPrefix("http://") && !text.hasPrefix("https://") {
                    text = "https://" + text
                }
                if let url = URL(string: text) {
                    authManager.serverURL = url
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Spacer()
        }
        .padding()
    }
}
