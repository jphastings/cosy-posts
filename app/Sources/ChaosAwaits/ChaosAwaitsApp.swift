import SwiftUI
import SwiftData

@main
struct ChaosAwaitsApp: App {
    let modelContainer: ModelContainer
    @State private var networkMonitor = NetworkMonitor()
    @State private var uploadManager: UploadManager

    init() {
        let container = try! ModelContainer(for: PendingPost.self)
        self.modelContainer = container

        // Default server URL -- will be configurable later
        let serverURL = URL(string: "http://localhost:8080")!
        let monitor = NetworkMonitor()
        self._networkMonitor = State(initialValue: monitor)
        self._uploadManager = State(
            initialValue: UploadManager(
                serverURL: serverURL,
                networkMonitor: monitor,
                modelContainer: container
            )
        )
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(networkMonitor)
                .environment(uploadManager)
                .task {
                    // Import any posts created by the share extension
                    await uploadManager.importSharedPosts()
                }
                .onReceive(NotificationCenter.default.publisher(for: UIApplication.willEnterForegroundNotification)) { _ in
                    Task {
                        await uploadManager.importSharedPosts()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
