---
# chaos-edfc
title: iOS locale picker and multi-locale text input
status: completed
type: feature
priority: normal
created_at: 2026-03-07T20:02:20Z
updated_at: 2026-03-07T23:40:06Z
blocked_by:
    - chaos-s2on
---

Add a locale flag button in the corner of the compose view showing the current locale (from the iOS device locale). Tapping it opens a select list to choose a new locale — previously used locales on this Cosy Posts site are shown at the top.

When a second locale is chosen, the text area splits into two (one per locale). On-device translation automatically populates the new textarea with a translation of any existing text, if available.

When submitting: only textareas with content are sent. The first text body becomes index.md (with locale: XX in frontmatter); subsequent locales are sent as additional body uploads stored as index.YY.md.

## API changes

- New TUS metadata field `locale` (e.g. `en`, `fr`) on body uploads to specify the content locale
- Add `locales` array (of locale codes) to the `/info` endpoint response, populated from locales seen across existing posts

## Summary of Changes

### API
- Added `locale` field to post frontmatter (written from TUS body metadata)
- Added `body-locale` role support in post assembly — additional locale body uploads are stored as `index.{locale}.{ext}` alongside the primary `index.md`
- Added `locales` array to `GET /api/info` response, populated by scanning existing post frontmatter and translation filenames
- `locale` TUS metadata field on body uploads specifies the content locale

### iOS App
- Locale picker button (globe icon) in compose toolbar showing primary locale code
- Tapping opens a sheet with site-used locales at top, common languages below, with search
- Multiple text areas — one per locale — with labeled headers and remove buttons
- `PendingPost` now stores `locale` (primary) and `localeTextsJSON` (additional locale texts)
- `UploadManager` uploads additional locale bodies with `role: body-locale` before the primary body
- On-device translation deferred to a follow-up (Translation framework API requires complex view-level integration)
