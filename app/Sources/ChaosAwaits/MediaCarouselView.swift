import SwiftUI

/// Scrollable grid showing selected media thumbnails with remove buttons.
struct MediaCarouselView: View {
    let items: [MediaItem]
    let onRemove: (UUID) -> Void

    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let size = itemSize(in: geo.size)
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: size, maximum: size), spacing: spacing)],
                    spacing: spacing
                ) {
                    ForEach(items) { item in
                        MediaThumbnailView(item: item, size: size) {
                            onRemove(item.id)
                        }
                    }
                }
                .padding(spacing)
            }
        }
    }

    private func itemSize(in containerSize: CGSize) -> CGFloat {
        let count = items.count
        // Show 3 columns for many items, 2 for a few, 1 for a single item
        let columns: CGFloat = count <= 1 ? 1 : count <= 4 ? 2 : 3
        return (containerSize.width - spacing * (columns + 1)) / columns
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
            .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
            }
            .offset(x: 4, y: -4)
        }
    }
}
