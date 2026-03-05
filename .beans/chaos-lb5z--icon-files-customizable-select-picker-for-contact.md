---
# chaos-lb5z
title: Icon files + customizable select picker for contact preferences
status: completed
type: task
priority: normal
created_at: 2026-03-05T08:07:38Z
updated_at: 2026-03-05T08:12:42Z
---

Extract contact method SVGs to files, size at 1.2em, replace header toggle button with appearance:base-select dropdown for enabling/disabling and prioritizing contact methods


## Summary of Changes

- Created `site/img/whatsapp.svg`, `site/img/signal.svg`, `site/img/email.svg` as editable icon files
- Added `img` passthrough copy in `.eleventy.js`
- Replaced inline SVG JS (`ICONS` object) with `<img src="/img/{type}.svg">` references
- Set icon sizing to `1.2em` via `.contact-icon img` CSS
- Replaced header rotate-button with `<select class="contact-pref-select">` using `appearance: base-select`
- Select shows all methods with rich HTML options (icon + label), enabled ones at top in full color, disabled ones dimmed
- Clicking an option toggles it enabled/disabled, reorders options, and updates all post contact buttons
- Header select is right-aligned via flex, distinct from title
