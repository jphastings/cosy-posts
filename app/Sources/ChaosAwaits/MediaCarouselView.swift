import SwiftUI

/// Scrollable grid showing selected media thumbnails with remove buttons.
struct MediaCarouselView: View {
    let items: [MediaItem]
    let onRemove: (UUID) -> Void

    private let spacing: CGFloat = 4

    var body: some View {
        GeometryReader { geo in
            let layout = gridLayout(for: items.count, in: geo.size)
            ScrollView {
                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.fixed(layout.cellSize), spacing: spacing),
                        count: layout.columns
                    ),
                    spacing: spacing
                ) {
                    ForEach(items) { item in
                        MediaThumbnailView(item: item, size: layout.cellSize) {
                            onRemove(item.id)
                        }
                    }
                }
                .padding(spacing)
            }
        }
    }

    private struct GridLayout {
        let columns: Int
        let cellSize: CGFloat
    }

    private func gridLayout(for count: Int, in size: CGSize) -> GridLayout {
        let cols: Int
        if count <= 1 {
            cols = 1
        } else if count <= 4 {
            cols = 2
        } else {
            cols = 3
        }
        let rows = Int(ceil(Double(count) / Double(cols)))

        let maxW = (size.width - spacing * CGFloat(cols + 1)) / CGFloat(cols)
        let maxH = (size.height - spacing * CGFloat(rows + 1)) / CGFloat(rows)

        return GridLayout(columns: cols, cellSize: min(maxW, maxH))
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
