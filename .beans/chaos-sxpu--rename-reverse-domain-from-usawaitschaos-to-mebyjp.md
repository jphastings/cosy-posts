---
# chaos-sxpu
title: Rename reverse domain from us.awaits.chaos to me.byjp.cosyposts
status: completed
type: task
priority: normal
created_at: 2026-03-07T21:54:42Z
updated_at: 2026-03-07T22:19:01Z
---

Replace all us.awaits.chaos reverse domain references with me.byjp.cosyposts throughout the project. This includes:
- iOS bundle identifiers (us.awaits.chaos.app → me.byjp.cosyposts.app, us.awaits.chaos.app.share → me.byjp.cosyposts.app.share)
- App Group identifier (group.us.awaits.chaos → group.me.byjp.cosyposts)
- Entitlements files
- project.yml bundleIdPrefix
- Any other references in Swift source or config files

## Summary of Changes

Replaced all `us.awaits.chaos` reverse domain references with `me.byjp.cosyposts`:
- `app/project.yml`: bundleIdPrefix and all bundle identifiers
- `app/Sources/CosyPostsAdmin/Info.plist`: URL type identifier
- `app/Sources/CosyPostsAdmin/CoSyPostsAdmin.entitlements`: app group
- `app/Sources/ShareExtension/ShareExtension.entitlements`: app group
- `app/Sources/CosyPostsAdmin/UploadManager.swift`: app group string
- `app/Sources/ShareExtension/ShareViewController.swift`: app group string
- `CLAUDE.md`: updated App Group reference and other stale docs
- Regenerated `CosyPostsAdmin.xcodeproj` via xcodegen
