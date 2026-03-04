import SwiftUI

/// Shows selected media at their original aspect ratio.
/// Single item fills the area; multiple items scroll horizontally.
struct MediaCarouselView: View {
    let items: [MediaItem]
    let onRemove: (UUID) -> Void

    var body: some View {
        GeometryReader { geo in
            if items.count == 1 {
                singleItem(items[0], in: geo.size)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(items) { item in
                            multiItem(item, height: geo.size.height)
                        }
                    }
                    .padding(.horizontal, 8)
                }
            }
        }
    }

    @ViewBuilder
    private func singleItem(_ item: MediaItem, in size: CGSize) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if item.loadingThumbnail {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.08))
                } else {
                    placeholder
                }
            }
            .frame(maxWidth: size.width, maxHeight: size.height)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            removeButton { onRemove(item.id) }
        }
    }

    @ViewBuilder
    private func multiItem(_ item: MediaItem, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let thumbnail = item.thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                } else if item.loadingThumbnail {
                    ProgressView()
                        .frame(width: height * 0.75, height: height)
                        .background(Color.secondary.opacity(0.08))
                } else {
                    placeholder
                        .frame(width: height * 0.75, height: height)
                }
            }
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            removeButton { onRemove(item.id) }
        }
    }

    private var placeholder: some View {
        Image(systemName: "photo")
            .font(.title)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.secondary.opacity(0.08))
    }

    private func removeButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.6))
        }
        .padding(4)
    }
}
