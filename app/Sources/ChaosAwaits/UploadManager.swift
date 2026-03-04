import Foundation
import SwiftData
import PhotosUI
import SwiftUI

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

    /// Enqueue a new post from the compose view.
    /// - Parameters:
    ///   - bodyText: The post body text.
    ///   - mediaItems: Selected media items from PHPicker.
    func enqueuePost(bodyText: String, mediaItems: [MediaItem]) async throws {
        let postID = Nanoid.generate()
        let context = ModelContext(modelContainer)

        // Save media to local files
        var mediaURLs: [URL] = []
        let postsDir = Self.localPostsDirectory()
        let postDir = postsDir.appendingPathComponent(postID)
        try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

        for (index, item) in mediaItems.enumerated() {
            if let data = try? await item.pickerItem.loadTransferable(type: Data.self) {
                let contentType = item.pickerItem.supportedContentTypes.first
                let ext = contentType?.preferredFilenameExtension ?? "bin"
                let filename = "media_\(index).\(ext)"
                let fileURL = postDir.appendingPathComponent(filename)
                try data.write(to: fileURL)
                mediaURLs.append(fileURL)
            }
        }

        let post = PendingPost(
            postID: postID,
            date: Date(),
            bodyText: bodyText,
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

                let metadata: [String: String] = [
                    "post-id": post.postID,
                    "filename": filename,
                    "content-type": contentType,
                ]

                _ = try await tusClient.uploadFile(data: data, metadata: metadata)

                post.mediaUploaded = index + 1
                try? context.save()
            }

            // Upload body text last (this triggers post assembly on the server)
            let bodyData = Data(post.bodyText.utf8)
            let bodyMetadata: [String: String] = [
                "post-id": post.postID,
                "filename": "body",
                "content-type": "text/plain",
                "role": "body",
                "date": dateString,
                "content-ext": post.contentExt,
            ]

            _ = try await tusClient.uploadFile(data: bodyData, metadata: bodyMetadata)

            post.postStatus = .completed
            post.errorMessage = nil
            try? context.save()

            // Clean up local media files
            cleanupLocalFiles(for: post)
        } catch {
            post.postStatus = .failed
            post.errorMessage = error.localizedDescription
            try? context.save()
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
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.us.awaits.chaos")
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
