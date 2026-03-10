import SwiftUI
import PhotosUI
import Photos
import AVFoundation
import UniformTypeIdentifiers
import os

private let mediaLog = Logger(subsystem: "com.cosyposts", category: "Media")

/// A single locale entry with its body text.
struct LocaleEntry: Identifiable {
    let id = UUID()
    var locale: Locale.Language
    var text: String = ""
    var isTranslating: Bool = false
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
    var isDropTargeted: Bool = false

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
        let existingIDs = Set(mediaItems.compactMap { $0.pickerItem?.itemIdentifier })
        let newItems = selectedPhotos.filter { item in
            guard let id = item.itemIdentifier else { return true }
            return !existingIDs.contains(id)
        }

        var newItemIDs: [UUID] = []
        for item in newItems {
            let mediaItem = MediaItem(pickerItem: item)
            mediaItems.append(mediaItem)
            newItemIDs.append(mediaItem.id)
        }

        // Remove picker items that were deselected (keep dropped items)
        let selectedIDs = Set(selectedPhotos.map { $0.itemIdentifier })
        mediaItems.removeAll { item in
            guard let pickerItem = item.pickerItem else { return false }
            return !selectedIDs.contains(pickerItem.itemIdentifier)
        }

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
        guard let index = mediaItems.firstIndex(where: { $0.id == id }),
              let pickerItem = mediaItems[index].pickerItem else { return }

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

    /// Handle dropped NSItemProviders from .onDrop.
    func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Try loading as a file URL first
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, error in
                    guard let data = data as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) else {
                        if let error { mediaLog.error("Drop URL load failed: \(error.localizedDescription)") }
                        return
                    }
                    Task { @MainActor in
                        self.addDroppedFile(url)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                // Image data directly (e.g. dragged from a browser)
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, error in
                    guard let data else {
                        if let error { mediaLog.error("Drop image load failed: \(error.localizedDescription)") }
                        return
                    }
                    Task { @MainActor in
                        self.addDroppedImageData(data)
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
                provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { url, error in
                    guard let url else {
                        if let error { mediaLog.error("Drop video load failed: \(error.localizedDescription)") }
                        return
                    }
                    Task { @MainActor in
                        self.addDroppedFile(url)
                    }
                }
            }
        }
    }

    /// Add a dropped file URL, copying it to a temp directory.
    private func addDroppedFile(_ url: URL) {
        let type = UTType(filenameExtension: url.pathExtension)
        let isMedia = type.map { t in t.conforms(to: .image) || t.conforms(to: .movie) || t.conforms(to: .audio) } ?? false
        guard isMedia else { return }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let dest = tempDir.appendingPathComponent(UUID().uuidString + "." + url.pathExtension)

        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }

        do {
            try FileManager.default.copyItem(at: url, to: dest)
        } catch {
            mediaLog.error("Failed to copy dropped file \(url.lastPathComponent): \(error.localizedDescription)")
            return
        }

        let item = MediaItem(fileURL: dest)
        mediaItems.append(item)
        Task { await loadDroppedThumbnail(for: item.id) }
    }

    /// Add dropped image data (not a file URL) by writing to temp.
    private func addDroppedImageData(_ data: Data) {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("dropped-media", isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        // Detect format from data
        let ext: String
        if data.count >= 8 {
            let header = [UInt8](data.prefix(8))
            if header.starts(with: [0x89, 0x50, 0x4E, 0x47]) { ext = "png" }
            else if header.starts(with: [0xFF, 0xD8]) { ext = "jpg" }
            else if header.starts(with: [0x47, 0x49, 0x46]) { ext = "gif" }
            else { ext = "jpg" }
        } else {
            ext = "jpg"
        }

        let dest = tempDir.appendingPathComponent(UUID().uuidString + "." + ext)
        do {
            try data.write(to: dest)
        } catch {
            mediaLog.error("Failed to write dropped image data: \(error.localizedDescription)")
            return
        }

        let item = MediaItem(fileURL: dest)
        mediaItems.append(item)
        Task { await loadDroppedThumbnail(for: item.id) }
    }

    /// Generate a thumbnail for a dropped file.
    private func loadDroppedThumbnail(for id: UUID) async {
        guard let index = mediaItems.firstIndex(where: { $0.id == id }),
              let fileURL = mediaItems[index].fileURL else { return }

        let type = UTType(filenameExtension: fileURL.pathExtension)

        if let type, type.conforms(to: .image) {
            // Load image thumbnail
            #if canImport(UIKit)
            if let data = try? Data(contentsOf: fileURL),
               let uiImage = UIImage(data: data) {
                if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                    mediaItems[idx].thumbnail = Image(uiImage: uiImage)
                    mediaItems[idx].loadingThumbnail = false
                }
                return
            }
            #elseif canImport(AppKit)
            if let nsImage = NSImage(contentsOf: fileURL) {
                if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                    mediaItems[idx].thumbnail = Image(nsImage: nsImage)
                    mediaItems[idx].loadingThumbnail = false
                }
                return
            }
            #endif
        } else if let type, type.conforms(to: .movie) {
            // Generate video thumbnail from first frame
            let asset = AVAsset(url: fileURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 512, height: 512)
            if let cgImage = try? await generator.image(at: .zero).image {
                let platformImage = PlatformImage(cgImage: cgImage)
                if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
                    mediaItems[idx].thumbnail = Image(platformImage: platformImage)
                    mediaItems[idx].loadingThumbnail = false
                }
                return
            }
        }

        mediaLog.warning("Could not generate thumbnail for dropped file \(fileURL.lastPathComponent)")
        if let idx = mediaItems.firstIndex(where: { $0.id == id }) {
            mediaItems[idx].loadingThumbnail = false
        }
    }

    /// Remove a media item at the given index.
    func removeMedia(at index: Int) {
        guard mediaItems.indices.contains(index) else { return }
        let removed = mediaItems.remove(at: index)
        if let pickerItem = removed.pickerItem {
            selectedPhotos.removeAll { $0.itemIdentifier == pickerItem.itemIdentifier }
        }
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
