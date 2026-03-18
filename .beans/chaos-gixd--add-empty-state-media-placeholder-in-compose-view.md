---
# chaos-gixd
title: Add empty-state media placeholder in compose view
status: completed
type: feature
priority: normal
created_at: 2026-03-18T20:53:28Z
updated_at: 2026-03-18T20:54:16Z
---

Show a tappable placeholder at min 25% height when no media is selected, inviting the user to add photos/videos.

## Summary of Changes

**ContentView.swift:**
- Added `MediaPlaceholderView`: icon + "Add Photos or Videos" text on subtle secondary background
- Modified the no-media `else` branch: placeholder in a PhotosPicker at min 25% height, divider, then text area filling the rest
