---
# chaos-stcu
title: CSS-driven media aspect ratios with pure Go video probing
status: completed
type: feature
priority: normal
created_at: 2026-03-10T17:19:25Z
updated_at: 2026-03-10T18:04:48Z
---

CSS-driven media carousel aspect ratios using server-side video probing. Pure Go MP4 metadata extraction (dimensions + GPS) via go-mp4 library. Aspect ratio stored in frontmatter and rendered via CSS custom property. No JS needed for layout.

## Summary of Changes\n\n- Added pure Go MP4 metadata extraction package (`api/video/`) using `go-mp4` library\n- Extracts video dimensions (VisualSampleEntry) and GPS location (©xyz atom)\n- Added `media_aspect_ratio` to post frontmatter, computed at assembly time\n- CSS custom property `--media-aspect-ratio` renders aspect ratio without JS\n- Removed JS video dimension fallback from base.html\n- Aspect ratio clamped between 4:5 (portrait) and 1.91:1 (landscape)\n- Render-time fallback probes images/videos for posts without frontmatter ratio
