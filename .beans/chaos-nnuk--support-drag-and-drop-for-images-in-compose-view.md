---
# chaos-nnuk
title: Support drag-and-drop for images in compose view
status: completed
type: feature
priority: normal
created_at: 2026-03-07T20:03:02Z
updated_at: 2026-03-10T11:26:16Z
---

Allow images, videos, and audio files to be dragged and dropped onto the media selection area of the compose view, as an alternative to using PHPicker. Dropped media should appear in the swipeable preview alongside any already-selected media.

## Summary of Changes

Added drag-and-drop support for media files in the compose view:

- **MediaItem**: Now supports both PhotosPickerItem and dropped file URLs (pickerItem is optional, fileURL added)
- **ComposeViewModel**: New `addDroppedFiles` method filters for image/video/audio UTTypes, copies to temp dir with security-scoped resource access, generates thumbnails (image loading for photos, AVAssetImageGenerator for videos)
- **ContentView**: `.dropDestination(for: URL.self)` on the media area accepts dropped files
- **UploadManager**: `exportMedia` handles file-URL items by copying directly to post directory (skips PHAsset pipeline)

Dropped media appears in the swipeable preview alongside picker-selected media. Picker deselection logic preserves dropped items.
