import Foundation
import SwiftData

/// Persistent model for a post waiting to be uploaded.
@Model
final class PendingPost {
    /// Unique post ID (nanoid).
    var postID: String

    /// ISO 8601 date declared by the uploader.
    var date: Date

    /// Post body text.
    var bodyText: String

    /// Content type for the body: "md" or "djot".
    var contentExt: String

    /// Current upload status.
    var status: String

    /// Local file URLs for media items, stored as JSON array of strings.
    var mediaURLsJSON: String

    /// Number of media items that have been uploaded successfully.
    var mediaUploaded: Int

    /// The TUS upload URL for the body text, if creation has started.
    var bodyUploadURL: String?

    /// Timestamp when the post was created.
    var createdAt: Date

    /// Timestamp of last status change.
    var updatedAt: Date

    /// Error message if the upload failed.
    var errorMessage: String?

    init(
        postID: String = Nanoid.generate(),
        date: Date = Date(),
        bodyText: String = "",
        contentExt: String = "md",
        mediaURLs: [URL] = []
    ) {
        self.postID = postID
        self.date = date
        self.bodyText = bodyText
        self.contentExt = contentExt
        self.status = PostStatus.pending.rawValue
        self.mediaURLsJSON = Self.encodeURLs(mediaURLs)
        self.mediaUploaded = 0
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    /// Decoded media file URLs.
    var mediaURLs: [URL] {
        get {
            guard let data = mediaURLsJSON.data(using: .utf8),
                  let strings = try? JSONDecoder().decode([String].self, from: data)
            else { return [] }
            return strings.compactMap { URL(string: $0) }
        }
        set {
            mediaURLsJSON = Self.encodeURLs(newValue)
        }
    }

    /// Current status as a typed enum.
    var postStatus: PostStatus {
        get { PostStatus(rawValue: status) ?? .pending }
        set {
            status = newValue.rawValue
            updatedAt = Date()
        }
    }

    private static func encodeURLs(_ urls: [URL]) -> String {
        let strings = urls.map { $0.absoluteString }
        guard let data = try? JSONEncoder().encode(strings),
              let json = String(data: data, encoding: .utf8)
        else { return "[]" }
        return json
    }
}

/// Upload status for a pending post.
enum PostStatus: String, Sendable {
    case pending
    case uploading
    case completed
    case failed
}
