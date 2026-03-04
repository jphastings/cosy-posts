---
# chaos-3krd
title: 'API: Post assembly & frontmatter'
status: completed
type: task
priority: normal
created_at: 2026-03-04T20:20:32Z
updated_at: 2026-03-04T20:49:18Z
parent: chaos-y7fz
blocked_by:
    - chaos-p3ki
    - chaos-vgt5
---

On body upload completion: create YYYY/MM/DD/{nanoid}/ directory, move+process media, extract EXIF GPS from first media with coords, extract #hashtags from text, write index.md/.djot with YAML frontmatter (date, lat/long, tags).
