---
# chaos-hw9d
title: Add server-side i18n with go-i18n
status: completed
type: feature
priority: normal
created_at: 2026-03-24T14:53:01Z
updated_at: 2026-03-24T15:01:25Z
---

Extract all English strings into TOML locale files using go-i18n v2. Templates use {{t .Lang "key"}}, JS reads from data-* attributes. Auth pages and notification emails also translated.


## Summary of Changes

Added server-side i18n using go-i18n v2 with embedded TOML locale files:

- New `api/internal/i18n/` package: thin wrapper around go-i18n Bundle/Localizer
- New `api/internal/i18n/locales/active.en.toml`: all ~63 English strings extracted
- Templates use `{{t .Lang "MessageID"}}` for all user-visible text
- JavaScript reads text from `data-*` attributes on DOM elements (no JS injection)
- Auth login pages and email templates use go-i18n localizers
- Notification emails use go-i18n pluralization (replaces manual buildSentence)
- `Post` struct has new `Lang` field for template access
- Language detected from Accept-Language header via existing `content.PreferredLang()`
