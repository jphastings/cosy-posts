---
# chaos-iwzb
title: 'Fix SVG icons: inline rendering for dark mode and sizing'
status: completed
type: bug
created_at: 2026-03-07T23:13:48Z
updated_at: 2026-03-07T23:13:48Z
---

SVG icons (bookmark, bookmarked, trash, contact method icons) were loaded via <img> tags which don't inherit CSS color — currentColor falls back to black, making icons invisible in dark mode. The trash icon also had no visible width. Fixed by inlining SVGs in the HTML output via a Go template function `{{icon "name"}}`, keeping the SVG files as editable sources. Updated all JS that previously swapped img.src to use CSS class toggles instead.
