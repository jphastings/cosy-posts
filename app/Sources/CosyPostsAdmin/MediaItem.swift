import SwiftUI
import PhotosUI
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

/// Represents a single media item selected from the photo picker.
struct MediaItem: Identifiable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    var thumbnail: Image?
    var loadingThumbnail: Bool = true
}
