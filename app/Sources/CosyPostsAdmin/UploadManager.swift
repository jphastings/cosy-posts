import Foundation
import SwiftData
import PhotosUI
@preconcurrency import Photos
import SwiftUI
@preconcurrency import AVFoundation
import UniformTypeIdentifiers
import os

private let uploadLog = Logger(subsystem: "com.cosyposts", category: "Upload")

/// Timeout for a single media export attempt.
private let exportTimeout: Duration = .seconds(60)

/// Manages the upload queue, processing pending posts when the network is available.
@Observable
@MainActor
final class UploadManager {
    /// The server's TUS endpoint URL.
    var serverURL: URL

    /// Whether an upload is currently in progress.
    private(set) var isProcessing: Bool = false

    private let networkMonitor: NetworkMonitor
    private let modelContainer: ModelContainer
    private var tusClient: TUSClient

    init(serverURL: URL, networkMonitor: NetworkMonitor, modelContainer: ModelContainer) {
        self.serverURL = serverURL
        self.networkMonitor = networkMonitor
        self.modelContainer = modelContainer
        self.tusClient = TUSClient(endpoint: serverURL.appendingPathComponent("files/"))
    }

    /// The authenticated user's email, sent as `author` metadata on uploads.
    var authorEmail: String?

    /// Update the server URL, auth token, and author email (called when auth state changes).
    func configure(serverURL: URL, authToken: String?, email: String?) async {
        self.serverURL = serverURL
        self.authorEmail = email
        self.tusClient = TUSClient(endpoint: serverURL.appendingPathComponent("files/"))
        await tusClient.setAuthToken(authToken)
    }

    /// Enqueue a new post from the compose view.
    /// - Parameters:
    ///   - localeEntries: Body text per locale (first entry is primary).
    ///   - mediaItems: Selected media items from PHPicker.
    func enqueuePost(localeEntries: [LocaleEntry], mediaItems: [MediaItem]) async throws {
        let postID = Nanoid.generate()
        let context = ModelContext(modelContainer)

        let postsDir = Self.localPostsDirectory()
        let postDir = postsDir.appendingPathComponent(postID)
        try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

        // Request Photos authorization once before processing all items.
        let photoAuthStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let hasPhotoAccess = photoAuthStatus == .authorized || photoAuthStatus == .limited

        var mediaURLs: [URL] = []
        var exportErrors: [String] = []

        for (index, item) in mediaItems.enumerated() {
            if let url = await exportMedia(item: item, index: index, postDir: postDir, hasPhotoAccess: hasPhotoAccess) {
                mediaURLs.append(url)
            } else {
                exportErrors.append("Failed to export media item \(index + 1)")
            }
        }

        if !exportErrors.isEmpty && mediaURLs.isEmpty {
            // All media failed — clean up and throw
            try? FileManager.default.removeItem(at: postDir)
            throw ExportError.allMediaFailed(exportErrors)
        }
        if !exportErrors.isEmpty {
            uploadLog.warning("Some media failed to export: \(exportErrors.joined(separator: ", "))")
        }

        let primaryLocale = localeEntries.first?.locale.languageCode?.identifier ?? "en"
        let primaryText = localeEntries.first?.text ?? ""

        var localeTexts: [String: String] = [:]
        for entry in localeEntries.dropFirst() {
            let text = entry.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if !text.isEmpty, let code = entry.locale.languageCode?.identifier {
                localeTexts[code] = entry.text
            }
        }

        let post = PendingPost(
            postID: postID,
            date: Date(),
            bodyText: primaryText,
            locale: primaryLocale,
            localeTexts: localeTexts,
            mediaURLs: mediaURLs
        )

        context.insert(post)
        try context.save()

        if networkMonitor.isConnected {
            await processQueue()
        }
    }

    // MARK: - Media Export Pipeline

    /// Export a single media item to a local file, trying multiple strategies.
    /// Returns the file URL on success, nil on failure.
    private func exportMedia(item: MediaItem, index: Int, postDir: URL, hasPhotoAccess: Bool) async -> URL? {
        let pickerItem = item.pickerItem
        let isVideo = pickerItem.supportedContentTypes.contains(where: { $0.conforms(to: .movie) })

        uploadLog.info("Exporting media \(index): isVideo=\(isVideo) types=\(pickerItem.supportedContentTypes.map(\.identifier))")

        // Strategy 1: Transferable (picker downloads from iCloud out-of-process)
        if let url = await exportViaTransferable(pickerItem: pickerItem, index: index, postDir: postDir, isVideo: isVideo) {
            uploadLog.info("Media \(index): exported via Transferable")
            return url
        }

        // Strategy 2+: PHAsset-based export
        if hasPhotoAccess, let identifier = pickerItem.itemIdentifier {
            let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
            if let asset = fetchResult.firstObject {
                if isVideo {
                    let fileURL = postDir.appendingPathComponent("media_\(index).mov")
                    if let url = await exportVideoWithTimeout(asset: asset, to: fileURL) {
                        uploadLog.info("Media \(index): exported video via AVExportSession")
                        return url
                    }
                } else {
                    // Strategy 2: requestImageDataAndOrientation (original bytes, best quality)
                    if let url = await exportViaImageData(asset: asset, index: index, postDir: postDir) {
                        uploadLog.info("Media \(index): exported via requestImageDataAndOrientation")
                        return url
                    }

                    // Strategy 3: requestImage with large targetSize (rendered, not original)
                    if let url = await exportViaRequestImage(asset: asset, index: index, postDir: postDir) {
                        uploadLog.info("Media \(index): exported via requestImage")
                        return url
                    }
                }
            }
        }

        uploadLog.error("Media \(index): all export strategies failed")
        return nil
    }

    /// Strategy 1: Use PhotosPicker's Transferable protocol.
    /// The picker runs out-of-process and handles iCloud downloads itself.
    private func exportViaTransferable(pickerItem: PhotosPickerItem, index: Int, postDir: URL, isVideo: Bool) async -> URL? {
        do {
            return try await withThrowingTaskGroup(of: URL?.self) { group in
                group.addTask {
                    // Try file-based transfer first (preserves original format)
                    if isVideo {
                        if let video = try? await pickerItem.loadTransferable(type: VideoTransferable.self) {
                            let dest = postDir.appendingPathComponent("media_\(index).mov")
                            try FileManager.default.copyItem(at: video.url, to: dest)
                            return dest
                        }
                    }
                    if let file = try? await pickerItem.loadTransferable(type: MediaFileTransferable.self) {
                        let ext = file.url.pathExtension.isEmpty ? "bin" : file.url.pathExtension
                        let dest = postDir.appendingPathComponent("media_\(index).\(ext)")
                        try FileManager.default.copyItem(at: file.url, to: dest)
                        return dest
                    }
                    // Try raw data transfer
                    if let data = try? await pickerItem.loadTransferable(type: Data.self) {
                        let contentType = pickerItem.supportedContentTypes.first
                        let ext = contentType?.preferredFilenameExtension ?? "bin"
                        let dest = postDir.appendingPathComponent("media_\(index).\(ext)")
                        try data.write(to: dest)
                        return dest
                    }
                    return nil
                }
                group.addTask {
                    try await Task.sleep(for: exportTimeout)
                    return nil
                }

                for try await result in group {
                    if let url = result {
                        group.cancelAll()
                        return url
                    }
                }
                group.cancelAll()
                return nil
            }
        } catch {
            uploadLog.warning("Media \(index): Transferable export failed: \(error.localizedDescription)")
            return nil
        }
    }

    /// Strategy 2: PHAsset requestImageDataAndOrientation — returns original image bytes.
    private func exportViaImageData(asset: PHAsset, index: Int, postDir: URL) async -> URL? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let result: (Data, UTType?)? = await withTimeout(exportTimeout) {
            await withCheckedContinuation { continuation in
                var resumed = false
                PHImageManager.default().requestImageDataAndOrientation(
                    for: asset,
                    options: options
                ) { data, uti, _, info in
                    guard !resumed else { return }
                    resumed = true

                    if let error = info?[PHImageErrorKey] as? NSError {
                        uploadLog.warning("Media \(index): requestImageData error: \(error.domain) \(error.code)")
                    }

                    if let data {
                        let utType = uti.flatMap { UTType($0) }
                        continuation.resume(returning: (data, utType))
                    } else {
                        continuation.resume(returning: nil)
                    }
                }
            }
        }

        guard let (data, utType) = result else { return nil }

        let ext = utType?.preferredFilenameExtension ?? "jpg"
        let fileURL = postDir.appendingPathComponent("media_\(index).\(ext)")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            uploadLog.error("Media \(index): failed to write image data: \(error.localizedDescription)")
            return nil
        }
    }

    /// Strategy 3: PHAsset requestImage with large target size — rendered image, not original bytes.
    /// Uses a 4096x4096 target rather than PHImageManagerMaximumSize to avoid iCloud download issues.
    private func exportViaRequestImage(asset: PHAsset, index: Int, postDir: URL) async -> URL? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat

        let targetSize = CGSize(width: 4096, height: 4096)

        let platformImage: PlatformImage? = await withTimeout(exportTimeout) {
            await withCheckedContinuation { continuation in
                var resumed = false
                PHImageManager.default().requestImage(
                    for: asset,
                    targetSize: targetSize,
                    contentMode: .aspectFit,
                    options: options
                ) { image, info in
                    guard !resumed else { return }
                    let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                    if isDegraded { return } // wait for full quality

                    resumed = true
                    if image == nil, let error = info?[PHImageErrorKey] as? NSError {
                        uploadLog.warning("Media \(index): requestImage error: \(error.domain) \(error.code)")
                    }
                    continuation.resume(returning: image)
                }
            }
        }

        guard let platformImage else { return nil }

        #if canImport(UIKit)
        let data = platformImage.jpegData(compressionQuality: 0.95)
        #else
        let cgImage = platformImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        let bitmapRep = cgImage.map { NSBitmapImageRep(cgImage: $0) }
        let data = bitmapRep?.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
        #endif

        guard let data else { return nil }

        let fileURL = postDir.appendingPathComponent("media_\(index).jpg")
        do {
            try data.write(to: fileURL)
            return fileURL
        } catch {
            uploadLog.error("Media \(index): failed to write rendered image: \(error.localizedDescription)")
            return nil
        }
    }

    /// Export a video asset with a timeout.
    private func exportVideoWithTimeout(asset: PHAsset, to fileURL: URL) async -> URL? {
        await withTimeout(exportTimeout) {
            await self.exportVideo(asset: asset, to: fileURL)
        }
    }

    /// Export a video asset to a file URL using AVAssetExportSession.
    private func exportVideo(asset: PHAsset, to fileURL: URL) async -> URL? {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .highQualityFormat

        // Step 1: Get the AVAsset via callback
        let wrapped: UncheckedSendable<AVAsset>? = await withCheckedContinuation { continuation in
            var resumed = false
            PHImageManager.default().requestAVAsset(
                forVideo: asset,
                options: videoOptions
            ) { avAsset, _, info in
                guard !resumed else { return }
                resumed = true
                if avAsset == nil, let error = info?[PHImageErrorKey] as? NSError {
                    uploadLog.warning("Video AVAsset request failed: \(error.domain) \(error.code)")
                }
                continuation.resume(returning: avAsset.map { UncheckedSendable(value: $0) })
            }
        }

        guard let avAsset = wrapped?.value else { return nil }

        // Step 2: Create export session and export
        guard let session = AVAssetExportSession(asset: avAsset, presetName: AVAssetExportPresetPassthrough) else {
            uploadLog.error("Failed to create AVAssetExportSession")
            return nil
        }

        do {
            try await session.export(to: fileURL, as: .mov)
            return fileURL
        } catch {
            uploadLog.error("Video export failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    // MARK: - Upload Queue

    /// Process all pending posts in the queue.
    func processQueue() async {
        guard !isProcessing else { return }
        guard networkMonitor.isConnected else { return }

        isProcessing = true
        defer { isProcessing = false }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PendingPost>(
            predicate: #Predicate { $0.status == "pending" || $0.status == "failed" },
            sortBy: [SortDescriptor(\.createdAt)]
        )

        guard let posts = try? context.fetch(descriptor) else { return }

        for post in posts {
            guard networkMonitor.isConnected else { break }
            await uploadPost(post, context: context)
        }
    }

    /// Upload a single post: media files first, then body text.
    private func uploadPost(_ post: PendingPost, context: ModelContext) async {
        post.postStatus = .uploading
        try? context.save()

        let dateFormatter = ISO8601DateFormatter()
        let dateString = dateFormatter.string(from: post.date)

        do {
            let mediaURLs = post.mediaURLs
            for (index, fileURL) in mediaURLs.enumerated() {
                guard index >= post.mediaUploaded else { continue }
                guard networkMonitor.isConnected else { return }

                let data = try Data(contentsOf: fileURL)
                let filename = fileURL.lastPathComponent
                let contentType = mimeType(for: fileURL)

                var metadata: [String: String] = [
                    "post-id": post.postID,
                    "filename": filename,
                    "content-type": contentType,
                ]
                if let author = authorEmail { metadata["author"] = author }

                _ = try await tusClient.uploadFile(data: data, metadata: metadata)

                post.mediaUploaded = index + 1
                try? context.save()
            }

            let localeTexts = post.localeTexts
            let sortedLocales = localeTexts.keys.sorted()
            for (index, localeCode) in sortedLocales.enumerated() {
                guard index >= post.localeBodyUploaded else { continue }
                guard networkMonitor.isConnected else { return }

                let text = localeTexts[localeCode] ?? ""
                let localeData = Data(text.utf8)
                var localeMetadata: [String: String] = [
                    "post-id": post.postID,
                    "filename": "body-\(localeCode)",
                    "content-type": "text/plain",
                    "role": "body-locale",
                    "locale": localeCode,
                    "content-ext": post.contentExt,
                ]
                if let author = authorEmail { localeMetadata["author"] = author }

                _ = try await tusClient.uploadFile(data: localeData, metadata: localeMetadata)

                post.localeBodyUploaded = index + 1
                try? context.save()
            }

            let bodyData = Data(post.bodyText.utf8)
            var bodyMetadata: [String: String] = [
                "post-id": post.postID,
                "filename": "body",
                "content-type": "text/plain",
                "role": "body",
                "date": dateString,
                "locale": post.locale,
                "content-ext": post.contentExt,
            ]
            if let author = authorEmail { bodyMetadata["author"] = author }

            _ = try await tusClient.uploadFile(data: bodyData, metadata: bodyMetadata)

            post.postStatus = .completed
            post.errorMessage = nil
            try? context.save()

            cleanupLocalFiles(for: post)
        } catch {
            uploadLog.error("Upload failed for post \(post.postID): \(error.localizedDescription)")
            post.postStatus = .failed
            post.errorMessage = error.localizedDescription
            try? context.save()
        }
    }

    // MARK: - Helpers

    private func mimeType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "gif": return "image/gif"
        case "mp4", "m4v": return "video/mp4"
        case "mov": return "video/quicktime"
        case "webp": return "image/webp"
        default: return "application/octet-stream"
        }
    }

    private func cleanupLocalFiles(for post: PendingPost) {
        let postsDir = Self.localPostsDirectory()
        let postDir = postsDir.appendingPathComponent(post.postID)
        try? FileManager.default.removeItem(at: postDir)
    }

    static func localPostsDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("pending_posts")
    }

    static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.me.byjp.cosyposts")
    }

    func importSharedPosts() async {
        guard let containerURL = Self.sharedContainerURL() else { return }

        let sharedPosts = SharedPost.pendingPosts(in: containerURL)
        guard !sharedPosts.isEmpty else { return }

        let context = ModelContext(modelContainer)

        for sharedPost in sharedPosts {
            let postsDir = Self.localPostsDirectory()
            let postDir = postsDir.appendingPathComponent(sharedPost.postID)
            try? FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

            var localMediaURLs: [URL] = []
            for filename in sharedPost.mediaFilenames {
                let sourceURL = sharedPost.mediaFileURL(filename: filename, in: containerURL)
                let destURL = postDir.appendingPathComponent(filename)
                if let _ = try? FileManager.default.copyItem(at: sourceURL, to: destURL) {
                    localMediaURLs.append(destURL)
                }
            }

            let formatter = ISO8601DateFormatter()
            let date = formatter.date(from: sharedPost.date) ?? Date()

            let post = PendingPost(
                postID: sharedPost.postID,
                date: date,
                bodyText: sharedPost.bodyText,
                contentExt: sharedPost.contentExt,
                mediaURLs: localMediaURLs
            )

            context.insert(post)
            sharedPost.remove(from: containerURL)
        }

        try? context.save()

        if networkMonitor.isConnected {
            await processQueue()
        }
    }
}

// MARK: - Timeout Helper

/// Run an async operation with a timeout. Returns nil if the timeout fires first.
private func withTimeout<T: Sendable>(_ duration: Duration, operation: @escaping @Sendable () async -> T?) async -> T? {
    await withTaskGroup(of: T?.self) { group in
        group.addTask { await operation() }
        group.addTask {
            try? await Task.sleep(for: duration)
            return nil
        }

        for await result in group {
            if let value = result {
                group.cancelAll()
                return value
            }
        }
        group.cancelAll()
        return nil
    }
}

// MARK: - Sendable Wrapper

/// Wraps a non-Sendable value for safe transfer across isolation boundaries.
/// Only use when you know the value won't be accessed concurrently.
private struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
}

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case allMediaFailed([String])

    var errorDescription: String? {
        switch self {
        case .allMediaFailed(let errors):
            return "Could not export media: \(errors.joined(separator: "; "))"
        }
    }
}
