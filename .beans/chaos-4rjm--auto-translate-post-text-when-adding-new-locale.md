---
# chaos-4rjm
title: Auto-translate post text when adding new locale
status: completed
type: feature
priority: normal
created_at: 2026-03-10T11:46:45Z
updated_at: 2026-03-10T14:01:36Z
---

Use Apple's Translation framework to auto-translate primary text into secondary locales. Show translation availability icons in locale picker (installed/downloadable/unsupported). Handle language pack downloads with spinner. Auto-translate when language is ready.

## Summary of Changes

New files:
- **TranslationManager.swift**: `@Observable` manager that wraps Apple's Translation framework. Tracks per-language availability status (installed/supported/downloading/unsupported). Manages `.translationTask` lifecycle via `translationConfig` + `pendingAction` pattern. Two actions: `prepare` (downloads model) and `translate` (translates text).

Modified files:
- **ContentView.swift**: Added `translationManager` state. `.translationTask` modifier handles prepare/translate actions. Source language synced from primary locale entry. Updated `LocalePickerSheet` instantiation with new `onSelect(language, canAutoTranslate)` signature — when auto-translate is true, triggers translation of primary text into new locale entry.
- **LocalePickerSheet**: Now receives `TranslationManager`. Checks availability on appear. Shows icons per language: bolt (installed), arrow.down.circle (downloadable), spinner (downloading), nothing (unsupported). Tap installed → select + auto-translate. Tap downloadable → start download, stay on sheet. Tap downloading → select without translation. Tap unsupported → select without translation.

## Summary of Changes

- Added TranslationManager using Apple's Translation framework for on-device translation
- Locale picker shows bolt icon for all translation-supported languages, checkmark for already-added locales
- Custom language code entry via search field (BCP 47 / ISO 639 codes like cy, en-GB, pt-BR)
- Skeleton shimmer animation while translation is in progress
- Translation config uses @State directly (not @Observable) to work with .translationTask modifier
- Config reset moved to after translation completes to avoid task cancellation
