import SwiftUI
import SwiftData

@main
struct CosyPostsAdminApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appState.authManager)
                .environment(appState.networkMonitor)
                .environment(appState.uploadManager)
                .task {
                    await appState.syncAuth()
                    await appState.uploadManager.importSharedPosts()
                }
                .onChange(of: appState.authManager.sessionToken) {
                    Task { await appState.syncAuth() }
                }
                .onOpenURL { url in
                    Task {
                        await appState.authManager.handleDeepLink(url)
                    }
                }
                .onReceive(NotificationCenter.default.publisher(for: .authSessionExpired)) { _ in
                    appState.authManager.logout()
                }
                #if canImport(UIKit)
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task {
                        await appState.uploadManager.importSharedPosts()
                    }
                }
                #endif
        }
        .modelContainer(appState.modelContainer)
    }
}

/// Routes between server setup, login, and the main compose view.
struct RootView: View {
    @Environment(AuthManager.self) private var authManager

    var body: some View {
        if !authManager.isAuthenticated {
            ServerSetupView()
        } else {
            ContentView()
        }
    }
}

/// Holds app-wide state, initialized lazily after the app process is running.
@Observable
@MainActor
final class AppState {
    let modelContainer: ModelContainer
    let networkMonitor: NetworkMonitor
    let uploadManager: UploadManager
    let authManager: AuthManager

    init() {
        let container = try! ModelContainer(for: PendingPost.self)
        self.modelContainer = container

        let monitor = NetworkMonitor()
        monitor.start()
        self.networkMonitor = monitor

        let auth = AuthManager()
        self.authManager = auth

        let serverURL = auth.serverURL ?? URL(string: "http://localhost:8080")!
        self.uploadManager = UploadManager(
            serverURL: serverURL,
            networkMonitor: monitor,
            modelContainer: container
        )
    }

    /// Sync auth state to the upload manager whenever auth changes.
    func syncAuth() async {
        guard let serverURL = authManager.serverURL else { return }
        await uploadManager.configure(serverURL: serverURL, authToken: authManager.sessionToken, email: authManager.email)
    }
}
