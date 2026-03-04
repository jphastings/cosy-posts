import SwiftUI
import SwiftData

@main
struct ChaosAwaitsApp: App {
    @State private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState.networkMonitor)
                .environment(appState.uploadManager)
                .task {
                    await appState.uploadManager.importSharedPosts()
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

/// Holds app-wide state, initialized lazily after the app process is running.
@Observable
@MainActor
final class AppState {
    let modelContainer: ModelContainer
    let networkMonitor: NetworkMonitor
    let uploadManager: UploadManager

    init() {
        let container = try! ModelContainer(for: PendingPost.self)
        self.modelContainer = container

        let monitor = NetworkMonitor()
        monitor.start()
        self.networkMonitor = monitor
        self.uploadManager = UploadManager(
            serverURL: URL(string: "http://localhost:8080")!,
            networkMonitor: monitor,
            modelContainer: container
        )
    }
}
