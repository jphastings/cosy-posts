---
# chaos-9tv0
title: 'Fix macOS media upload: iCloud Photos sandbox restriction'
status: in-progress
type: bug
priority: high
created_at: 2026-03-08T11:53:34Z
updated_at: 2026-03-08T11:54:48Z
---

Media uploads fail on macOS when Photos library uses 'Optimize Mac Storage' (iCloud Photos). All Photos framework APIs fail with `CloudPhotoLibraryErrorDomain error 1005` in sandboxed apps.

## Problem

When the Mac's Photos library is set to "Optimize Mac Storage", photo originals live in iCloud. The app can get small cached thumbnails but cannot download full-size originals for upload. This affects ALL media types (HEIC, PNG, JPEG, MOV).

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
