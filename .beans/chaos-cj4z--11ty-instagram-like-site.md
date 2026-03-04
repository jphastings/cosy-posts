---
# chaos-cj4z
title: 11ty Instagram-like site
status: completed
type: feature
priority: normal
created_at: 2026-03-04T22:50:57Z
updated_at: 2026-03-04T23:04:37Z
---

Create an 11ty static site in site/ with Instagram-style feed, swipeable media carousel, WhatsApp share button, and light/dark mode support.

## Summary of Changes\n\nCreated 11ty site in site/ with:\n- Instagram-style single-column feed, reverse-chronological\n- Pure CSS swipeable carousel (scroll-snap + ::scroll-marker dots, zero JS)\n- WhatsApp share button per post\n- Light/dark mode via prefers-color-scheme\n- Custom data loader parsing content/**/index.md frontmatter + sibling media\n- API rebuild command updated to run eleventy\n- API triggers site rebuild on startup
