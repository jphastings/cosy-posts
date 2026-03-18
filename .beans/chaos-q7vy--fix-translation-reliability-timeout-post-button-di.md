---
# chaos-q7vy
title: 'Fix translation reliability: timeout, post-button disable, standard skeleton'
status: completed
type: bug
priority: normal
created_at: 2026-03-18T20:06:15Z
updated_at: 2026-03-18T20:09:47Z
---

Translation sometimes fails silently leaving skeleton stuck. Need: (1) timeout so users can type if translation hangs, (2) disable Post button during translation, (3) standard iOS shimmer skeleton instead of unconventional pulse animation, (4) fix error path not clearing isTranslating.

## Summary of Changes

**ContentView.swift:**
- Fixed translation failure path: `.translationTask` catch block now clears `isTranslating` so skeleton doesn't get stuck
- Added 10-second timeout: a parallel Task clears the skeleton if translation hasn't completed, letting the user type manually
- Replaced custom pulsing skeleton with standard iOS sliding shimmer (LinearGradient highlight that sweeps left-to-right in a continuous loop)

**ComposeViewModel.swift:**
- Added `isTranslating` computed property that checks if any locale entry is mid-translation
- `canUpload` now returns false while any translation is in progress, which disables the Post button
