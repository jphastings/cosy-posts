import SwiftUI
import PhotosUI

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

    /// Load a thumbnail image for a media item.
    private func loadThumbnail(for id: UUID) async {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }) else { return }
        let item = mediaItems[index]

        if let data = try? await item.pickerItem.loadTransferable(type: Data.self),
           let platformImage = PlatformImage(data: data) {
            let thumbnail = Image(platformImage: platformImage)
            if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                mediaItems[idx].thumbnail = thumbnail
                mediaItems[idx].loadingThumbnail = false
            }
        } else {
            if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                mediaItems[idx].loadingThumbnail = false
            }
        }
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
