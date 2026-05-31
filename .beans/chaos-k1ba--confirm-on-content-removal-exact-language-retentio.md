---
# chaos-k1ba
title: Confirm-on-content removal + exact language retention + tests
status: completed
type: task
priority: normal
created_at: 2026-05-31T06:52:38Z
updated_at: 2026-05-31T07:49:54Z
---

Language selection follow-ups from branch review: (1) persist exact promoted language (region/script preserved, not base code); (2) confirm before removing any language (primary or secondary) that has content; (3) add behavioral unit tests for ComposeViewModel locale logic.

## Summary of Changes

- **Exact language retention (#1):** `savePreferredStartingLanguage` now stores `language.minimalIdentifier` instead of the base `languageCode`, matching the sibling draft-persistence code. This retains a chosen script/region (Traditional Chinese round-trips; `en-GB` stays `en-GB`) instead of collapsing to `zh`/`en`. Device-equivalence is compared at the same minimal granularity so keeping the default doesn't store a redundant override. (An initial attempt to decompose into explicit subtags was reverted — `Locale.Language.script` returns an *inferred* value, e.g. `cy`→`cy-Latn`, adding noise.)
- **Confirm-on-content removal (#2):** the confirm-when-content path already gated both primary and secondary removals; hardened the alert copy — destructive button names the language ("Remove {language}"), and the message warns when removing the primary also changes the default language for future posts.
- **Behavioral unit tests (#4):** added `Tests/UploadTests/ComposeViewModelTests.swift` (10 tests): remove guards, primary promotion, active-locale follow, exact script + region retention, override persistence/fallback/clearing. Full UploadTests suite: 22 passed, 0 failures (macOS).
