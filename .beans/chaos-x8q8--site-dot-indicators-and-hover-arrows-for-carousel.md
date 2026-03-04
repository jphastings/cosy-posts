---
# chaos-x8q8
title: 'Site: dot indicators and hover arrows for carousel'
status: completed
type: feature
priority: normal
created_at: 2026-03-04T23:08:57Z
updated_at: 2026-03-04T23:10:05Z
---

Add dot indicators beneath carousel images (muted dots, active dot brighter) and prev/next arrows visible on hover. Use CSS ::scroll-marker for dots and ::scroll-button for arrows.

## Summary of Changes\n\nAdded to site carousel CSS:\n- Dot indicators beneath images using ::scroll-marker (muted dots, active dot brighter/scaled)\n- Prev/next arrow buttons using ::scroll-button, visible on hover, hidden at edges\n- Both dots and arrows hidden for single-image posts\n- Dots use theme-aware colors (var(--text) / var(--text-secondary))
