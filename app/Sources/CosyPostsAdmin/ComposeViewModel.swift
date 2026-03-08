import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import os

private let mediaLog = Logger(subsystem: "com.cosyposts", category: "Media")

/// A single locale entry with its body text.
struct LocaleEntry: Identifiable {
    let id = UUID()
    var locale: Locale.Language
    var text: String = ""
}

/// View model for the compose/post creation screen.
@Observable
@MainActor
final class ComposeViewModel {
    var mediaItems: [MediaItem] = []
    var localeEntries: [LocaleEntry] = [
        LocaleEntry(locale: Locale.current.language)
    ]
    var selectedPhotos: [PhotosPickerItem] = [] {
        didSet {
            handlePickerSelection()
        }
    }
    var isUploading: Bool = false
    var showingLocalePicker: Bool = false

    /// The primary body text (first locale entry).
    var bodyText: String {
        get { localeEntries.first?.text ?? "" }
        set {
            if localeEntries.isEmpty {
                localeEntries.append(LocaleEntry(locale: Locale.current.language))
            }
            localeEntries[0].text = newValue
        }
    }

    /// Whether the post has any content worth uploading (and no items are still downloading).
    var canUpload: Bool {
        let hasContent = !mediaItems.isEmpty || localeEntries.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasContent && !hasDownloadingItems
    }

    /// The primary locale code (e.g. "en").
    var primaryLocaleCode: String {
        localeEntries.first?.locale.languageCode?.identifier ?? "en"
    }

    /// Add a new locale for translation.
    func addLocale(_ language: Locale.Language) {
        guard !localeEntries.contains(where: { $0.locale == language }) else { return }
        localeEntries.append(LocaleEntry(locale: language))
    }

    /// Remove a locale entry by ID (cannot remove the primary).
    func removeLocale(id: UUID) {
        guard localeEntries.count > 1 else { return }
        guard localeEntries.first?.id != id else { return }
        localeEntries.removeAll { $0.id == id }
    }

    /// Handle new selections from PHPicker, adding items that aren't already present.
    private func handlePickerSelection() {
        let existingIDs = Set(mediaItems.map { $0.pickerItem.itemIdentifier })
        let newItems = selectedPhotos.filter { !existingIDs.contains($0.itemIdentifier) }

        var newItemIDs: [UUID] = []
        for item in newItems {
            let mediaItem = MediaItem(pickerItem: item)
            mediaItems.append(mediaItem)
            newItemIDs.append(mediaItem.id)
        }

        // Remove items that were deselected in the picker
        let selectedIDs = Set(selectedPhotos.map { $0.itemIdentifier })
        mediaItems.removeAll { !selectedIDs.contains($0.pickerItem.itemIdentifier) }

        // Request Photos authorization once, then load all thumbnails.
        if !newItemIDs.isEmpty {
            Task {
                await PHPhotoLibrary.requestAuthorization(for: .readWrite)
                for itemID in newItemIDs {
                    await loadThumbnail(for: itemID)
                }
            }
        }
    }

    /// Whether any media items are still downloading from iCloud.
    var hasDownloadingItems: Bool {
        mediaItems.contains { $0.isDownloading }
    }

    /// Load a thumbnail progressively: show degraded first, then update with full quality.
    private func loadThumbnail(for id: UUID) async {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }) else { return }
        let pickerItem = mediaItems[index].pickerItem

        // Try PHAsset path first (works reliably on macOS sandbox).
        if let identifier = pickerItem.itemIdentifier {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                let targetSize = CGSize(width: 512, height: 512)
                let options = PHImageRequestOptions()
                options.deliveryMode = .opportunistic
                options.isNetworkAccessAllowed = true
                options.version = .current

                let stream = AsyncStream<(PlatformImage?, Bool)> { continuation in
                    PHImageManager.default().requestImage(
                        for: asset,
                        targetSize: targetSize,
                        contentMode: .aspectFit,
                        options: options
                    ) { image, info in
                        let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                        continuation.yield((image, isDegraded))
                        if !isDegraded {
                            continuation.finish()
                        }
                    }
                }

                for await (platformImage, isDegraded) in stream {
                    guard let idx = mediaItems.firstIndex(where: { $0.id == id }) else { break }
                    if let platformImage {
                        mediaItems[idx].thumbnail = Image(platformImage: platformImage)
                    }
                    if isDegraded {
                        mediaItems[idx].isDownloading = true
                        mediaItems[idx].loadingThumbnail = false
                    } else {
                        mediaItems[idx].isDownloading = false
                        mediaItems[idx].loadingThumbnail = false
                    }
                }
                return
            }
        }

        // Fallback: try Transferable (works on iOS).
        if let image = try? await pickerItem.loadTransferable(type: Image.self) {
            if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                mediaItems[idx].thumbnail = image
                mediaItems[idx].loadingThumbnail = false
            }
            return
        }

        mediaLog.error("Thumbnail loading failed for item \(id)")
        if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
            mediaItems[idx].loadingThumbnail = false
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
        let entries = localeEntries

        Task {
            do {
                try await uploadManager.enqueuePost(localeEntries: entries, mediaItems: items)
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
        localeEntries = [LocaleEntry(locale: Locale.current.language)]
        isUploading = false
    }
}
