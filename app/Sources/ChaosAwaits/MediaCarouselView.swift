import SwiftUI

/// Horizontally scrollable carousel showing selected media thumbnails with remove buttons.
struct MediaCarouselView: View {
    let items: [MediaItem]
    let onRemove: (UUID) -> Void

    private let thumbnailSize: CGFloat = 120

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: 12) {
                ForEach(items) { item in
                    MediaThumbnailView(item: item, size: thumbnailSize) {
                        onRemove(item.id)
                    }
                }
            }
            .padding(.horizontal)
        }
        .frame(height: thumbnailSize + 16)
    }
}

/// Individual thumbnail for a media item with a remove button overlay.
struct MediaThumbnailView: View {
    let item: MediaItem
    let size: CGFloat
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if item.loadingThumbnail {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.15))
                } else {
                    Image(systemName: "photo")
                        .font(.title)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.15))
                }
            }
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 6, y: -6)
        }
    }
}
