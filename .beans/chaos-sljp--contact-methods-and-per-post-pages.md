---
# chaos-sljp
title: Contact methods and per-post pages
status: completed
type: feature
priority: normal
created_at: 2026-03-05T07:37:20Z
updated_at: 2026-03-05T07:51:59Z
---

Author-specific contact buttons (WhatsApp/Signal/email) per post, preference toggle in header, per-post pages at /p/{id}/, author in frontmatter, CAN_POST_CSV env var for 11ty

## Summary of Changes

### API
- `api/post/assemble.go`: Added `Author` field to Frontmatter, populated from TUS metadata
- `api/auth/auth.go`: Added `email` to `/auth/verify` JSON response; changed session expiry to 180 days
- `api/rebuild/rebuild.go`: Set `CAN_POST_CSV` env var pointing to `can-post.csv` for 11ty

### iOS App
- `AuthManager.swift`: Store `email` from verify response in UserDefaults
- `UploadManager.swift`: Send `author` metadata on all TUS uploads
- `ChaosAwaitsApp.swift`: Pass email through to upload manager

### Site
- `_data/members.js` (new): Parses CAN_POST_CSV, returns email→{name, methods} map with CSV column order
- `_data/posts.js`: Added `author` field to post objects
- `_includes/post-card.njk` (new): Shared post card partial with contact button
- `post.njk` (new): Per-post pages via 11ty pagination at `/p/{id}/`
- `index.njk`: Uses post-card partial, added header preference toggle button
- `css/style.css`: Contact button styles, header flex layout, method-specific icon colors
- `_includes/base.njk`: Full JS for contact method resolution, localStorage preference management, header toggle, SVG icons
