---
# chaos-idc7
title: 'Rework compose view: media, text panel, language picker'
status: completed
type: feature
priority: normal
created_at: 2026-03-18T19:36:16Z
updated_at: 2026-03-18T19:39:26Z
---

Rework the photos & text compose interface: 1) Only show media carousel when media is added, 2) Cap media at 75% screen height, 3) Single rotating text panel with language name top-right that cycles on tap, 4) Language picker becomes toggle sheet with checkmarks, 5) Confirmation dialog when disabling language with content


## Summary of Changes

### ComposeViewModel.swift
- Added `activeLocaleID` and computed `activeLocaleIndex` for tracking the currently visible locale in the rotating text panel
- Added `cycleLocale()` method to rotate through enabled locales
- `addLocale` now switches to the newly added locale
- `removeLocale` switches away from the active locale before removing it
- `reset` clears `activeLocaleID`

### ContentView.swift
- **Media area**: Only shows carousel when media items exist (no empty state placeholder). Wrapped in GeometryReader with `maxHeight: 75%` cap. Drop target moved to entire content area.
- **Text panel**: Single `LocaleTextArea` showing the active locale. Language name moved to top-right, tappable to cycle through enabled locales. Chevron indicator when multiple locales exist. No more X remove button.
- **Language picker**: Renamed to "Languages" with "Done" button. Shows checkmarks for enabled languages. Tapping enabled non-primary language toggles it off (with confirmation dialog if it has content). Tapping disabled language adds it (with auto-translate if available). Primary language shown as non-removable with "Primary" label.
