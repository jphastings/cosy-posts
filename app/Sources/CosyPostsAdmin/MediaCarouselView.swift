import SwiftUI

/// Shows selected media one item at a time with paging.
/// Single item fills the width; multiple items are inset to 95% width with
/// a 1.25% gap between them, revealing a sliver of the next item.
struct MediaCarouselView: View {
    let items: [MediaItem]
    let onRemove: (UUID) -> Void
    @State private var visibleItemID: UUID?

    private var currentIndex: Int {
        guard let visibleItemID,
              let idx = items.firstIndex(where: { $0.id == visibleItemID }) else { return 0 }
        return idx
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            if items.count == 1 {
                itemContent(items[0], width: w, height: h)
                    .frame(width: w, height: h)
            } else {
                let itemWidth = w * 0.95
                let spacing = w * 0.0125
                let inset = w * 0.025

                ZStack(alignment: .topLeading) {
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: spacing) {
                            ForEach(items) { item in
                                itemContent(item, width: itemWidth, height: h)
                                    .frame(width: itemWidth, height: h)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $visibleItemID)
                    .contentMargins(.horizontal, inset, for: .scrollContent)
                    .scrollTargetBehavior(.viewAligned)

                    // Page indicator
                    Text("\(currentIndex + 1)/\(items.count)")
                        .font(.caption2.weight(.medium).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.black.opacity(0.5), in: .capsule)
                        .padding(8)
                }
            }
        }
    }

    @ViewBuilder
    private func itemContent(_ item: MediaItem, width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                if let thumbnail = item.thumbnail {
                    thumbnail
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: width, maxHeight: height)
                } else if item.loadingThumbnail {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.secondary.opacity(0.08))
                } else {
                    placeholder
                }

                if item.isDownloading {
                    downloadingOverlay
                }
            }
            .frame(width: width, height: height)
            .clipped()

            removeButton { onRemove(item.id) }
        }
    }

    private var downloadingOverlay: some View {
        VStack(spacing: 6) {
            ProgressView()
                .controlSize(.small)
            Text("iCloud")
                .font(.caption2)
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
                .font(.title2)
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .gray)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .contentShape(.circle)
        .frame(minWidth: 44, minHeight: 44)
        .padding(2)
    }
}
