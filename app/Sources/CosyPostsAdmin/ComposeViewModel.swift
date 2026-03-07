import SwiftUI
import PhotosUI
import AVFoundation

/// View model for the compose/post creation screen.
@Observable
@MainActor
final class ComposeViewModel {
    var mediaItems: [MediaItem] = []
    var bodyText: String = ""
    var selectedPhotos: [PhotosPickerItem] = [] {
        didSet {
            handlePickerSelection()
        }
    }
    var isUploading: Bool = false

    /// Whether the post has any content worth uploading.
    var canUpload: Bool {
        !mediaItems.isEmpty || !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Handle new selections from PHPicker, adding items that aren't already present.
    private func handlePickerSelection() {
        let existingIDs = Set(mediaItems.map { $0.pickerItem.itemIdentifier })
        let newItems = selectedPhotos.filter { !existingIDs.contains($0.itemIdentifier) }

        for item in newItems {
            let mediaItem = MediaItem(pickerItem: item)
            mediaItems.append(mediaItem)
            let itemID = mediaItem.id
            Task {
                await loadThumbnail(for: itemID)
            }
        }

        // Remove items that were deselected in the picker
        let selectedIDs = Set(selectedPhotos.map { $0.itemIdentifier })
        mediaItems.removeAll { !selectedIDs.contains($0.pickerItem.itemIdentifier) }
    }

    /// Load a thumbnail image for a media item (supports both images and videos).
    private func loadThumbnail(for id: UUID) async {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }) else { return }
        let item = mediaItems[index]

        var thumbnail: Image?

        // Try loading as image data first.
        if let data = try? await item.pickerItem.loadTransferable(type: Data.self),
           let platformImage = PlatformImage(data: data) {
            thumbnail = Image(platformImage: platformImage)
        }

        // If that failed, try loading as a video and generating a thumbnail frame.
        if thumbnail == nil,
           let videoURL = try? await item.pickerItem.loadTransferable(type: VideoTransferable.self) {
            thumbnail = await generateVideoThumbnail(url: videoURL.url)
        }

        if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
            mediaItems[idx].thumbnail = thumbnail
            mediaItems[idx].loadingThumbnail = false
        }
    }

    /// Generate a thumbnail from the first frame of a video.
    private nonisolated func generateVideoThumbnail(url: URL) async -> Image? {
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 512, height: 512)

        guard let cgImage = try? await generator.image(at: .zero).image else {
            return nil
        }

        let platformImage = PlatformImage(cgImage: cgImage)
        return Image(platformImage: platformImage)
    }

    /// Remove a media item at the given index.
    func removeMedia(at index: Int) {
        guard mediaItems.indices.contains(index) else { return }
        let removed = mediaItems.remove(at: index)
        selectedPhotos.removeAll { $0.itemIdentifier == removed.pickerItem.itemIdentifier }
    }

    /// Remove a media item by its ID.
    func removeMedia(id: UUID) {
        if let index = mediaItems.firstIndex(where: { $0.id == id }) {
            removeMedia(at: index)
        }
    }

    /// Error message to display to the user.
    var errorMessage: String?

    /// Initiate the upload process for the current post.
    func upload(using uploadManager: UploadManager) {
        guard canUpload else { return }
        isUploading = true
        errorMessage = nil

        let items = mediaItems
        let text = bodyText

        Task {
            do {
                try await uploadManager.enqueuePost(bodyText: text, mediaItems: items)
                reset()
            } catch {
                errorMessage = error.localizedDescription
                isUploading = false
            }
        }
    }

    /// Reset the compose form after a successful upload.
    func reset() {
        mediaItems.removeAll()
        selectedPhotos.removeAll()
        bodyText = ""
        isUploading = false
    }
}
