---
# chaos-ewj3
title: Fix video thumbnail preview in iOS compose view
status: completed
type: bug
priority: normal
created_at: 2026-03-07T20:02:45Z
updated_at: 2026-03-07T22:21:32Z
---

When a video is selected via PHPicker in the compose view, no thumbnail is shown in the swipeable preview. Videos should display a generated thumbnail frame so users can see what they've selected before uploading.

## Summary of Changes

Added video thumbnail generation in the iOS compose view. When a video is selected via PHPicker, AVAssetImageGenerator extracts a frame from the video to display as a thumbnail preview.

Changes:
- `ComposeViewModel.swift`: loadThumbnail now falls back to video thumbnail generation via AVAssetImageGenerator when image loading fails
- `MediaItem.swift`: Added `VideoTransferable` type for receiving video file URLs from the photo picker, and `NSImage(cgImage:)` convenience init for macOS
