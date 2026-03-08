import Foundation
import SwiftData
import PhotosUI
import Photos
import SwiftUI
import AVFoundation
import os

private let uploadLog = Logger(subsystem: "com.cosyposts", category: "Upload")

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

        // Save media to local files
        var mediaURLs: [URL] = []
        let postsDir = Self.localPostsDirectory()
        let postDir = postsDir.appendingPathComponent(postID)
        try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

        // Request Photos authorization once before processing all items.
        let photoAuthStatus = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        let hasPhotoAccess = photoAuthStatus == .authorized || photoAuthStatus == .limited

        for (index, item) in mediaItems.enumerated() {
            var exported = false

            // Try PHAsset export (handles iCloud downloads).
            if hasPhotoAccess, let identifier = item.pickerItem.itemIdentifier {
                let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil)
                if let asset = fetchResult.firstObject {
                    if asset.mediaType == .video {
                        // Export video via AVAssetExportSession.
                        let fileURL = postDir.appendingPathComponent("media_\(index).mov")
                        if let url = await exportVideo(asset: asset, to: fileURL) {
                            mediaURLs.append(url)
                            exported = true
                        }
                    } else {
                        // Export image via PHImageManager.requestImage at full size.
                        // requestImageDataAndOrientation fails in sandbox with iCloud Photos,
                        // but requestImage with max size works and returns a usable image.
                        let imageOptions = PHImageRequestOptions()
                        imageOptions.isNetworkAccessAllowed = true
                        imageOptions.deliveryMode = .highQualityFormat

                        let platformImage: PlatformImage? = await withCheckedContinuation { continuation in
                            var resumed = false
                            PHImageManager.default().requestImage(
                                for: asset,
                                targetSize: PHImageManagerMaximumSize,
                                contentMode: .default,
                                options: imageOptions
                            ) { image, info in
                                guard !resumed else { return }
                                let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
                                if !isDegraded {
                                    resumed = true
                                    if image == nil, let error = info?[PHImageErrorKey] as? NSError {
                                        uploadLog.error("requestImage failed: \(error.domain, privacy: .public) \(error.code, privacy: .public)")
                                    }
                                    continuation.resume(returning: image)
                                }
                            }
                        }

                        if let platformImage {
                            #if canImport(UIKit)
                            let data = platformImage.jpegData(compressionQuality: 0.95)
                            #else
                            let cgImage = platformImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
                            let bitmapRep = cgImage.map { NSBitmapImageRep(cgImage: $0) }
                            let data = bitmapRep?.representation(using: .jpeg, properties: [.compressionFactor: 0.95])
                            #endif

                            if let data {
                                let fileURL = postDir.appendingPathComponent("media_\(index).jpg")
                                try data.write(to: fileURL)
                                mediaURLs.append(fileURL)
                                exported = true
                            }
                        }
                    }
                }
            }

            // Fallback: try Transferable (works on iOS).
            if !exported {
                let contentType = item.pickerItem.supportedContentTypes.first
                let ext = contentType?.preferredFilenameExtension ?? "bin"
                let filename = "media_\(index).\(ext)"
                let fileURL = postDir.appendingPathComponent(filename)

                if let mediaFile = try? await item.pickerItem.loadTransferable(type: MediaFileTransferable.self) {
                    try FileManager.default.copyItem(at: mediaFile.url, to: fileURL)
                    mediaURLs.append(fileURL)
                } else if let data = try? await item.pickerItem.loadTransferable(type: Data.self) {
                    try data.write(to: fileURL)
                    mediaURLs.append(fileURL)
                }
            }
        }

        let primaryLocale = localeEntries.first?.locale.languageCode?.identifier ?? "en"
        let primaryText = localeEntries.first?.text ?? ""

        // Build locale texts dict for additional locales (skip primary, skip empty).
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

        // Start processing if we're online
        if networkMonitor.isConnected {
            await processQueue()
        }
    }

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
            // Upload media files first
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

            // Upload additional locale bodies first (role=body-locale, does NOT trigger assembly).
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

            // Upload primary body text last (this triggers post assembly on the server).
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

            // Clean up local media files
            cleanupLocalFiles(for: post)
        } catch {
            uploadLog.error("Upload failed for post \(post.postID): \(error.localizedDescription)")
            post.postStatus = .failed
            post.errorMessage = error.localizedDescription
            try? context.save()
        }
    }

    /// Get the file extension for a PHAsset based on its resource.
    private func extensionForAsset(_ asset: PHAsset) -> String {
        let resources = PHAssetResource.assetResources(for: asset)
        if let resource = resources.first {
            let filename = resource.originalFilename
            if let ext = filename.split(separator: ".").last {
                return String(ext).lowercased()
            }
        }
        return "jpg"
    }

    /// Export a video asset to a file URL using AVAssetExportSession.
    private func exportVideo(asset: PHAsset, to fileURL: URL) async -> URL? {
        let videoOptions = PHVideoRequestOptions()
        videoOptions.isNetworkAccessAllowed = true
        videoOptions.deliveryMode = .highQualityFormat

        return await withCheckedContinuation { continuation in
            PHImageManager.default().requestExportSession(
                forVideo: asset,
                options: videoOptions,
                exportPreset: AVAssetExportPresetPassthrough
            ) { session, _ in
                guard let session else {
                    continuation.resume(returning: nil)
                    return
                }
                session.outputURL = fileURL
                session.outputFileType = .mov
                session.exportAsynchronously {
                    if session.status == .completed {
                        continuation.resume(returning: fileURL)
                    } else {
                        uploadLog.error("Video export failed: \(session.error?.localizedDescription ?? "unknown", privacy: .public)")
                        continuation.resume(returning: nil)
                    }
                }
            }
        }
    }

    /// Get the MIME type for a file based on its extension.
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

    /// Remove local media files after successful upload.
    private func cleanupLocalFiles(for post: PendingPost) {
        let postsDir = Self.localPostsDirectory()
        let postDir = postsDir.appendingPathComponent(post.postID)
        try? FileManager.default.removeItem(at: postDir)
    }

    /// Directory for storing local copies of media files before upload.
    static func localPostsDirectory() -> URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documents.appendingPathComponent("pending_posts")
    }

    /// Shared App Group container for share extension communication.
    static func sharedContainerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.me.byjp.cosyposts")
    }

    /// Import posts created by the share extension from the shared container.
    func importSharedPosts() async {
        guard let containerURL = Self.sharedContainerURL() else { return }

        let sharedPosts = SharedPost.pendingPosts(in: containerURL)
        guard !sharedPosts.isEmpty else { return }

        let context = ModelContext(modelContainer)

        for sharedPost in sharedPosts {
            // Copy media files to local posts directory
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

            // Remove the shared post from the container
            sharedPost.remove(from: containerURL)
        }

        try? context.save()

        // Process the queue if online
        if networkMonitor.isConnected {
            await processQueue()
        }
    }
}
