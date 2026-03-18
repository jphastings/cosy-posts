---
# chaos-endd
title: 'Upgrade carousel: aspect-ratio sizing, paging, peek'
status: completed
type: feature
priority: normal
created_at: 2026-03-18T20:29:00Z
updated_at: 2026-03-18T20:30:49Z
---

Show one media item at a time. Panel height matches average aspect ratio (max 75%). Multi-item: 95% width items with 2.5% outer padding and 1.25% inter-item gap showing a peek of next item.

## Summary of Changes

**MediaItem.swift:** Added `aspectRatio: CGFloat?` property (width/height).

**ComposeViewModel.swift:**
- Capture aspect ratio from PHAsset pixel dimensions, UIImage/NSImage size, and CGImage dimensions (covers picker, dropped images, and video thumbnails)
- Added `averageMediaAspectRatio` computed property (falls back to 4:3)

**MediaCarouselView.swift:** Rewritten:
- Single item: full width, fills the panel at its aspect ratio
- Multiple items: paging ScrollView with `scrollTargetBehavior(.viewAligned)`, each item 95% width, 1.25% gap, 2.5% outer inset — shows peek of next item

**ContentView.swift:** Media panel height now computed as `width / averageAspectRatio` clamped to 75% of available height. Text area fills remaining space.
