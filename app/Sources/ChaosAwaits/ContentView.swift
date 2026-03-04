import SwiftUI
import SwiftData
import PhotosUI

struct ContentView: View {
    @State private var viewModel = ComposeViewModel()
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
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            .navigationTitle("New Post")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
    }
}

#Preview {
    ContentView()
        .environment(NetworkMonitor())
        .environment(
            UploadManager(
                serverURL: URL(string: "http://localhost:8080")!,
                networkMonitor: NetworkMonitor(),
                modelContainer: try! ModelContainer(for: PendingPost.self)
            )
        )
}
