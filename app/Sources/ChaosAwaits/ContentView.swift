import SwiftUI
import PhotosUI

struct ContentView: View {
    @State private var viewModel = ComposeViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Media carousel (shown when items are selected)
                if !viewModel.mediaItems.isEmpty {
                    MediaCarouselView(
                        items: viewModel.mediaItems,
                        onRemove: { id in viewModel.removeMedia(id: id) }
                    )
                    .padding(.vertical, 8)

                    Divider()
                }

                // Text input area
                TextEditor(text: $viewModel.bodyText)
                    .frame(maxHeight: .infinity)
                    .padding(.horizontal, 4)
                    .overlay(alignment: .topLeading) {
                        if viewModel.bodyText.isEmpty {
                            Text("What's on your mind?")
                                .foregroundStyle(.tertiary)
                                .padding(.top, 8)
                                .padding(.leading, 8)
                                .allowsHitTesting(false)
                        }
                    }

                Divider()

                // Bottom toolbar: picker + upload button
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

                    Button(action: { viewModel.upload() }) {
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
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

#Preview {
    ContentView()
}
