---
# chaos-s2on
title: Multilingual post storage and serving
status: completed
type: feature
priority: normal
created_at: 2026-03-07T20:02:11Z
updated_at: 2026-03-07T21:06:07Z
---

Support multiple locales per post. The primary text is stored as index.md with a locale: XX frontmatter field (driven by the iOS app's current locale). Additional translations are stored as index.YY.md (no frontmatter — the index.md holds all frontmatter). When using the built-in template system, the Accept-Language header selects the best matching locale; when an external build system is configured, locale handling is delegated to it.

## Summary of Changes\n\nImplemented as part of chaos-t3u0 work:\n\n- Posts support `locale` frontmatter field on `index.md` (defaults to "en")\n- Translation files `index.{lang}.md` are detected and parsed alongside the primary post\n- Post cards show language tab pills when translations exist, with JS to switch between them\n- Accept-Language header is parsed and used to auto-select the best matching locale on page load\n- `Vary: Accept-Language` response header set for correct caching\n- External build systems are unaffected (locale data is in the content files for them to use)
