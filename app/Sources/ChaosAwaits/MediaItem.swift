import SwiftUI
import PhotosUI

/// Represents a single media item selected from the photo picker.
struct MediaItem: Identifiable {
    let id = UUID()
    let pickerItem: PhotosPickerItem
    var thumbnail: Image?
    var loadingThumbnail: Bool = true
}
