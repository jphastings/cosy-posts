---
# chaos-x8q8
title: 'Site: dot indicators and hover arrows for carousel'
status: completed
type: feature
priority: normal
created_at: 2026-03-04T23:08:57Z
updated_at: 2026-03-04T23:21:48Z
---

Add dot indicators beneath carousel images (muted dots, active dot brighter) and prev/next arrows visible on hover. Use CSS ::scroll-marker for dots and ::scroll-button for arrows.

## Summary of Changes\n\nAdded to site carousel CSS:\n- Dot indicators beneath images using ::scroll-marker (muted dots, active dot brighter/scaled)\n- Prev/next arrow buttons using ::scroll-button, visible on hover, hidden at edges\n- Both dots and arrows hidden for single-image posts\n- Dots use theme-aware colors (var(--text) / var(--text-secondary))

## Summary of Changes\n\nReplaced CSS-only ::scroll-marker/::scroll-button (Chrome 135+ only) with HTML dots + arrows + small inline JS that works in all browsers:\n- Dot indicators beneath carousel, active dot highlighted\n- Prev/next arrow buttons appear on hover, disabled at edges\n- touch-action: pan-x to prevent vertical scroll capture in carousel\n- Hidden for single-image posts
