---
# chaos-f7yj
title: Fix landscape video whitespace on website
status: completed
type: bug
priority: normal
created_at: 2026-03-08T11:55:06Z
updated_at: 2026-03-09T09:35:33Z
---

When displaying a landscape video on the website, the video card has excessive white space above and below the video. The card should fit snugly around the video content, matching its aspect ratio rather than using a fixed/square container.

## Summary of Changes

Video-only carousels now adapt their aspect ratio to match the video's natural dimensions (clamped between 4:5 portrait and 16:9 landscape). Added JS in base.html that detects video-only carousels and updates the aspect ratio once video metadata loads, eliminating excessive whitespace around landscape videos.
