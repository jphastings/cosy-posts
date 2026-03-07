---
# chaos-edfc
title: iOS locale picker and multi-locale text input
status: draft
type: feature
created_at: 2026-03-07T20:02:20Z
updated_at: 2026-03-07T20:02:20Z
blocked_by:
    - chaos-s2on
---

Add a locale flag button in the corner of the compose view showing the current locale (from the iOS device locale). Tapping it opens a select list to choose a new locale — previously used locales on this Cosy Posts site are shown at the top.

When a second locale is chosen, the text area splits into two (one per locale). On-device translation automatically populates the new textarea with a translation of any existing text, if available.

When submitting: only textareas with content are sent. The first text body becomes index.md (with locale: XX in frontmatter); subsequent locales are sent as additional body uploads stored as index.YY.md.
