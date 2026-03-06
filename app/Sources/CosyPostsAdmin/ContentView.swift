import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @State private var viewModel = ComposeViewModel()
    @State private var showingSiteSheet = false
    @Environment(AuthManager.self) private var authManager
    @Environment(UploadManager.self) private var uploadManager
    @Environment(NetworkMonitor.self) private var networkMonitor

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Offline banner
                if !networkMonitor.isConnected {
                    HStack {
                        Image(systemName: "wifi.slash")
                        Text("Offline -- posts will upload when connected")
                            .font(.caption)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(.orange)
                }

                // Media area — takes up most of the space
                PhotosPicker(
                    selection: $viewModel.selectedPhotos,
                    maxSelectionCount: 20,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Group {
                        if viewModel.mediaItems.isEmpty {
                            // Empty state — tap to add media
                            VStack(spacing: 12) {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.system(size: 40))
                                Text("Tap to select photos or videos")
                                    .font(.subheadline)
                            }
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(Color.secondary.opacity(0.08))
                        } else {
                            // Media carousel
                            MediaCarouselView(
                                items: viewModel.mediaItems,
                                onRemove: { id in viewModel.removeMedia(id: id) }
                            )
                        }
                    }
                }
                .buttonStyle(.plain)
                .frame(maxHeight: .infinity)

                Divider()

                // Text input — compact area at the bottom
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $viewModel.bodyText)
                        .font(.body)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 4)
                        .frame(minHeight: 60, maxHeight: 100)

                    if viewModel.bodyText.isEmpty {
                        Text("What's on your mind?")
                            .font(.body)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 8)
                            .padding(.leading, 9)
                            .allowsHitTesting(false)
                    }
                }

                // Error message
                if let error = viewModel.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text(error)
                            .font(.caption)
                    }
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 4)
                }

                Divider()

                // Bottom toolbar
                ZStack {
                    // Center: site name button
                    Button {
                        showingSiteSheet = true
                    } label: {
                        Text(authManager.serverURL?.host ?? "Not connected")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)

                    // Left and right edges
                    HStack {
                        PhotosPicker(
                            selection: $viewModel.selectedPhotos,
                            maxSelectionCount: 20,
                            matching: .any(of: [.images, .videos]),
                            photoLibrary: .shared()
                        ) {
                            Label("Add Media", systemImage: "photo.on.rectangle.angled")
                                .font(.body)
                        }

                        Spacer()

                        if uploadManager.isProcessing {
                            Label("Uploading...", systemImage: "arrow.up.circle")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button(action: { viewModel.upload(using: uploadManager) }) {
                            if viewModel.isUploading {
                                ProgressView()
                                    .controlSize(.small)
                                    .padding(.horizontal, 12)
                            } else {
                                Text("Post")
                                    .fontWeight(.semibold)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(!viewModel.canUpload || viewModel.isUploading)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .navigationTitle("New Post")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .sheet(isPresented: $showingSiteSheet) {
                SiteInfoSheet(authManager: authManager)
                    .presentationDetents([.medium])
            }
        }
    }
}

struct SiteInfo: Decodable {
    let name: String
    let version: String
    let gitSHA: String
    let stats: SiteStats

    enum CodingKeys: String, CodingKey {
        case name, version
        case gitSHA = "git_sha"
        case stats
    }
}

struct SiteStats: Decodable {
    let posts: Int
    let photos: Int
    let videos: Int
    let audio: Int
}

@Observable
@MainActor
final class SiteInfoLoader {
    var info: SiteInfo?
    var isLoading = false

    func load(serverURL: URL, token: String?) async {
        isLoading = true
        defer { isLoading = false }

        let url = serverURL.appendingPathComponent("api/info")
        var request = URLRequest(url: url)
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            info = try JSONDecoder().decode(SiteInfo.self, from: data)
        } catch {
            // Silently fail — sheet shows what it can
        }
    }
}

struct SiteInfoSheet: View {
    let authManager: AuthManager
    @Environment(\.dismiss) private var dismiss
    @State private var loader = SiteInfoLoader()

    private var repoURL: URL? {
        guard let sha = loader.info?.gitSHA, sha != "unknown" else { return nil }
        return URL(string: "https://github.com/jphastings/cosy-posts/commit/\(sha)")
    }

    var body: some View {
        NavigationStack {
            List {
                if let info = loader.info {
                    // Stats
                    Section {
                        Label {
                            Text("\(info.stats.posts) posts")
                        } icon: {
                            Image(systemName: "doc.richtext")
                        }
                        .foregroundStyle(.primary)

                        if info.stats.photos > 0 {
                            Label {
                                Text("\(info.stats.photos) photos")
                            } icon: {
                                Image(systemName: "photo")
                            }
                            .foregroundStyle(.primary)
                        }

                        if info.stats.videos > 0 {
                            Label {
                                Text("\(info.stats.videos) videos")
                            } icon: {
                                Image(systemName: "film")
                            }
                            .foregroundStyle(.primary)
                        }

                        if info.stats.audio > 0 {
                            Label {
                                Text("\(info.stats.audio) sound clips")
                            } icon: {
                                Image(systemName: "waveform")
                            }
                            .foregroundStyle(.primary)
                        }
                    } header: {
                        Text("Content")
                    }
                } else if loader.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView()
                            Spacer()
                        }
                    }
                }

                // Logout
                Section {
                    Button(role: .destructive) {
                        authManager.logout()
                        dismiss()
                    } label: {
                        Label("Log Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }

                // Version footer
                if let info = loader.info {
                    Section {
                        if let repoURL {
                            Link(destination: repoURL) {
                                Text("v\(info.version) (\(info.gitSHA))")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                            }
                        } else {
                            Text("v\(info.version)")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .listRowBackground(Color.clear)
                }
            }
            .navigationTitle(loader.info?.name ?? authManager.serverURL?.host ?? "Site Info")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task {
                guard let serverURL = authManager.serverURL else { return }
                await loader.load(serverURL: serverURL, token: authManager.sessionToken)
            }
        }
    }
}

#Preview {
    ContentView()
        .environment(AuthManager())
        .environment(NetworkMonitor())
        .environment(
            UploadManager(
                serverURL: URL(string: "http://localhost:8080")!,
                networkMonitor: NetworkMonitor(),
                modelContainer: try! ModelContainer(for: PendingPost.self)
            )
        )
}
