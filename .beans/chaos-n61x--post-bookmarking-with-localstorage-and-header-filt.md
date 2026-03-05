---
# chaos-n61x
title: Post bookmarking with localStorage and header filter
status: completed
type: feature
priority: normal
created_at: 2026-03-05T12:13:17Z
updated_at: 2026-03-05T12:18:52Z
---

Bookmark posts via localStorage, toggle filled/outline icon, header filter button to show only bookmarked posts


## Summary of Changes

- `site/_includes/base.njk`: Added bookmark JS — localStorage storage (JSON array of post IDs), toggle on click, icon swap between bookmark.svg/bookmarked.svg, header filter to show only bookmarked posts
- `site/index.njk`: Added `.bookmark-filter-btn` to header (left of select)
- `site/css/style.css`: Shared styles for `.bookmark-btn` and `.bookmark-filter-btn`, active state for filter
