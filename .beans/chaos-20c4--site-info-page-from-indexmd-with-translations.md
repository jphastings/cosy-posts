---
# chaos-20c4
title: Site info page from index.md with translations
status: completed
type: feature
priority: normal
created_at: 2026-03-07T23:00:32Z
updated_at: 2026-03-07T23:18:05Z
---

The site's index.md (and locale variants index.<locale>.md) should serve as an info/about dialog for the site, not a post.

## Behaviour

- A heroicons information-circle icon appears immediately to the right of the site name
- Tapping/clicking it opens a dialog/sheet displaying the rendered content of index.md
- If locale-specific variants exist (e.g. index.fr.md), show the one matching the user's locale, falling back to index.md
- The index.md file lives in the content directory root, not in a post directory

## Tasks

- [x] Add index.md support to the API (store/serve site-level markdown, not as a post)
- [x] Add info-circle icon next to site name on the website
- [x] Render index.md content in a dialog/overlay on the website
- [ ] Add info-circle button next to site name in the iOS app (deferred to chaos-TBD)
- [ ] Show index.md content in a sheet in the iOS app (deferred to chaos-TBD)
- [x] Support locale fallback for translations

## Summary of Changes

- Added `info.svg` (Heroicons information-circle) to embedded static assets
- Added `{{icon "info"}}` template function support
- `serveHome` loads `index.md` from content dir root, renders via goldmark, passes to template
- Root-level `index.md` is excluded from post listing
- Locale fallback: tries `index.{lang}.md` before `index.md`
- Info button appears in header only when `index.md` exists
- Info content shown in a styled `<dialog>` overlay
- Added `GET /api/info/site` endpoint returning rendered HTML (for iOS app)
- iOS app tasks deferred to a follow-up bean
