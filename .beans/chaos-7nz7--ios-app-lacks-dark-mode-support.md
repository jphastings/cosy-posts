---
# chaos-7nz7
title: iOS app lacks dark mode support
status: completed
type: bug
priority: low
created_at: 2026-03-08T00:04:10Z
updated_at: 2026-03-08T08:19:19Z
---

The iOS app doesn't appear to have dark mode styling, at least in the simulator. Investigate whether this needs explicit dark mode support or if SwiftUI defaults should handle it.

## Summary of Changes\n\nNo code changes needed. The app uses SwiftUI semantic colors throughout, which automatically adapt to dark mode. The simulator was likely set to light mode — toggled it to dark to verify.
