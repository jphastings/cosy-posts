import SwiftUI
import PhotosUI
import CoreTransferable
#if canImport(UIKit)
import UIKit
typealias PlatformImage = UIImage
extension Image {
    init(platformImage: PlatformImage) { self.init(uiImage: platformImage) }
}
#elseif canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
extension Image {
    init(platformImage: PlatformImage) { self.init(nsImage: platformImage) }
}
#endif

#if canImport(AppKit) && !targetEnvironment(macCatalyst)
extension NSImage {
    /// Create an NSImage from a CGImage, used for video thumbnail generation.
    convenience init(cgImage: CGImage) {
        self.init(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
    }
}
#endif

/// Represents a single media item — either from the photo picker or a dropped file.
struct MediaItem: Identifiable {
    let id = UUID()
    /// Set when the item came from PhotosPicker.
    var pickerItem: PhotosPickerItem?
    /// Set when the item came from drag-and-drop (a local file URL).
    var fileURL: URL?
    var thumbnail: Image?
    var loadingThumbnail: Bool = true
    /// True while a high-quality version is being downloaded from iCloud.
    var isDownloading: Bool = false

    init(pickerItem: PhotosPickerItem) {
        self.pickerItem = pickerItem
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        self.loadingThumbnail = true
    }
}

/// A transferable type that receives a file URL from the photo picker (any media type).
struct MediaFileTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .data) { file in
            SentTransferredFile(file.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let dest = tempDir.appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}

/// A transferable type that receives a video file URL from the photo picker.
struct VideoTransferable: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(contentType: .movie) { video in
            SentTransferredFile(video.url)
        } importing: { received in
            let tempDir = FileManager.default.temporaryDirectory
            let dest = tempDir.appendingPathComponent(received.file.lastPathComponent)
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: received.file, to: dest)
            return Self(url: dest)
        }
    }
}
