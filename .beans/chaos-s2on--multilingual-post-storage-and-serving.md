---
# chaos-s2on
title: Multilingual post storage and serving
status: draft
type: feature
created_at: 2026-03-07T20:02:11Z
updated_at: 2026-03-07T20:02:11Z
---

Support multiple locales per post. The primary text is stored as index.md with a locale: XX frontmatter field (driven by the iOS app's current locale). Additional translations are stored as index.YY.md (no frontmatter — the index.md holds all frontmatter). When using the built-in template system, the Accept-Language header selects the best matching locale; when an external build system is configured, locale handling is delegated to it.
