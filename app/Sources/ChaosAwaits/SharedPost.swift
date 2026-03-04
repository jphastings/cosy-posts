import Foundation

/// A post created by the share extension, stored in the shared App Group container.
/// The main app picks these up and enqueues them for upload.
struct SharedPost: Codable, Sendable {
    /// Unique post ID (nanoid).
    let postID: String

    /// ISO 8601 date when the post was created.
    let date: String

    /// Post body text.
    let bodyText: String

    /// Filenames of media files stored in the shared container's post directory.
    let mediaFilenames: [String]

    /// Content type extension for the body ("md" or "djot").
    let contentExt: String

    init(
        postID: String = Nanoid.generate(),
        date: Date = Date(),
        bodyText: String = "",
        mediaFilenames: [String] = [],
        contentExt: String = "md"
    ) {
        self.postID = postID
        let formatter = ISO8601DateFormatter()
        self.date = formatter.string(from: date)
        self.bodyText = bodyText
        self.mediaFilenames = mediaFilenames
        self.contentExt = contentExt
    }

    /// The directory name within the shared container for this post's files.
    var directoryName: String { postID }

    /// Read all pending shared posts from the shared container.
    static func pendingPosts(in containerURL: URL) -> [SharedPost] {
        let inboxURL = containerURL.appendingPathComponent("inbox")
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: inboxURL, includingPropertiesForKeys: nil
        ) else { return [] }

        return entries.compactMap { dir in
            let manifestURL = dir.appendingPathComponent("post.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let post = try? JSONDecoder().decode(SharedPost.self, from: data)
            else { return nil }
            return post
        }
    }

    /// Save this shared post manifest and its media to the shared container.
    func save(to containerURL: URL) throws {
        let inboxURL = containerURL.appendingPathComponent("inbox")
        let postDir = inboxURL.appendingPathComponent(directoryName)
        try FileManager.default.createDirectory(at: postDir, withIntermediateDirectories: true)

        let manifestURL = postDir.appendingPathComponent("post.json")
        let data = try JSONEncoder().encode(self)
        try data.write(to: manifestURL)
    }

    /// Remove this shared post from the shared container after it has been imported.
    func remove(from containerURL: URL) {
        let inboxURL = containerURL.appendingPathComponent("inbox")
        let postDir = inboxURL.appendingPathComponent(directoryName)
        try? FileManager.default.removeItem(at: postDir)
    }

    /// Get the full file URL for a media file within the shared container.
    func mediaFileURL(filename: String, in containerURL: URL) -> URL {
        let inboxURL = containerURL.appendingPathComponent("inbox")
        return inboxURL
            .appendingPathComponent(directoryName)
            .appendingPathComponent(filename)
    }
}
