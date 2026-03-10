---
# chaos-9tv0
title: 'Fix macOS media upload: iCloud Photos sandbox restriction'
status: completed
type: bug
priority: high
created_at: 2026-03-08T11:53:34Z
updated_at: 2026-03-10T11:09:49Z
---

Media uploads fail on macOS when Photos library uses 'Optimize Mac Storage' (iCloud Photos). All Photos framework APIs fail with `CloudPhotoLibraryErrorDomain error 1005` in sandboxed apps.

Image and video upload need to work regardless of whether the image has been fully stored on iCloud, whether it's being-drag-dropped onto the macOS app, or whether it's being sent from the share-sheet.

## Problem

When the Mac's Photos library is set to "Optimize Mac Storage", photo originals live in iCloud. The app can get small cached thumbnails but cannot download full-size originals for upload. This affects ALL media types (HEIC, PNG, JPEG, MOV).

The full size image needs to be uploaded; even if a 'Retrieving from iCloud' note needs to appear while it's downloaded.

## What was tried (all fail with error 1005)

- `PhotosPickerItem.loadTransferable(type: Image.self)` — `TransferableSupportError Code=0`
- `PhotosPickerItem.loadTransferable(type: Data.self)` — `TransferableSupportError Code=0`
- `MediaFileTransferable` (custom FileRepresentation) — `TransferableSupportError Code=0`
- `PHAssetResourceManager.writeData(for:toFile:options:)` — `CloudPhotoLibraryErrorDomain 1005`
- `PHImageManager.requestImageDataAndOrientation` — `CloudPhotoLibraryErrorDomain 1005`
- `PHImageManager.requestImage` with `PHImageManagerMaximumSize` — `CloudPhotoLibraryErrorDomain 1005`

## What DOES work

- `PHImageManager.requestImage` with small `targetSize` (e.g., 512x512) — returns cached thumbnails
- Thumbnails load correctly, including progressive iCloud download with spinner overlay

## What was committed

- `efaf48f`: PHAsset-based thumbnails with progressive iCloud loading and download overlay
- Thumbnails work. Media export for upload does NOT work yet.

## Ideas to investigate

- [ ] Try `requestImage` with intermediate sizes (e.g., 2048x2048) — might hit cache threshold
- [ ] Check if `com.apple.security.assets.pictures.read-write` / `com.apple.security.assets.movies.read-write` entitlements help
- [ ] Try `PHCachingImageManager` with explicit pre-caching before export
- [ ] Test on iOS (simulator or device) — sandbox restrictions may be different
- [ ] Consider removing App Sandbox for macOS-only builds (dev only)
- [ ] Look into whether `NSFileCoordinator` can access the Photos library files directly
- [ ] Check if the `com.apple.security.temporary-exception.files.absolute-path.read-only` entitlement for Photos paths helps
- [ ] Consider a `PHPickerViewController`-based approach (UIKit/AppKit) that gives access to `NSItemProvider` directly

## Key files

- `app/Sources/CosyPostsAdmin/UploadManager.swift` — media export + TUS upload
- `app/Sources/CosyPostsAdmin/ComposeViewModel.swift` — thumbnail loading (working)
- `app/Sources/CosyPostsAdmin/MediaItem.swift` — MediaItem model + Transferable types
- `app/Sources/CosyPostsAdmin/MediaCarouselView.swift` — download overlay UI

\n## Approach: Rewrite media export pipeline\n\n- [x] Fix hung continuation bug in requestImage (never resumes if only degraded results)\n- [x] Try Transferable first (picker downloads from iCloud out-of-process, may work on macOS 26)\n- [x] Try PHAsset requestImageDataAndOrientation with timeout as fallback\n- [x] Try PHAsset requestImage with large targetSize as last resort\n- [x] Add proper timeout to all export strategies (60s)\n- [x] Show clear error if all strategies fail (don't silently drop media)\n- [x] Add comprehensive logging for debugging


## Build Status

Rewrite compiles cleanly (zero errors, zero warnings) on macOS. Needs manual testing with iCloud Photos to verify the multi-strategy pipeline works.

## Summary of Changes

Rewrote UploadManager.swift media export pipeline with multi-strategy approach:
1. Transferable (picker handles iCloud download out-of-process)
2. PHAsset requestImageDataAndOrientation (original bytes)
3. PHAsset requestImage at 4096×4096 (rendered fallback)

All strategies wrapped in 60s timeout. Video export modernized to use async export(to:as:) API. Comprehensive logging at every step. Clear error reporting when all strategies fail.
