---
# chaos-a0o7
title: Add posted toast notification
status: completed
type: feature
priority: normal
created_at: 2026-03-19T22:13:33Z
updated_at: 2026-03-19T22:15:29Z
---

Show a brief native toast/notification when a post is successfully uploaded, on both iOS and macOS.


## Summary of Changes

**ContentView.swift:**
- Added `showPostedToast` state that triggers when `isUploading` transitions from true to false with no error
- Green capsule toast slides down from the top with "Posted!" checkmark, auto-dismisses after 2.5s
- Haptic feedback via `.sensoryFeedback(.success, ...)` on iOS
