---
# chaos-5v9z
title: 'Fix EXIF preservation: use magic byte format detection'
status: completed
type: bug
priority: normal
created_at: 2026-03-04T22:35:15Z
updated_at: 2026-03-04T22:35:21Z
---

EXIF metadata not preserved when processing HEIC-originated uploads. Root cause: format detection used file extension but iOS PhotosPicker converts HEIC→JPEG while keeping .heic extension, so goheif.ExtractExif was called on JPEG data and silently failed. Fix: use magic byte detection for all format-dependent operations.

## Summary of Changes\n\nRewrote `api/photo/process.go` to detect image format via magic bytes instead of file extension:\n- Added `detectFormat()` reading first 12 bytes (JPEG: FF D8 FF, PNG: 89 50 4E 47, HEIC: ftyp box)\n- All format-dependent code (decoding, EXIF extraction, orientation handling) now branches on detected format\n- Fixes the case where iOS PhotosPicker converts HEIC→JPEG but keeps the .heic extension
