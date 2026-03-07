---
# chaos-sxpu
title: Rename reverse domain from us.awaits.chaos to me.byjp.cosyposts
status: draft
type: task
created_at: 2026-03-07T21:54:42Z
updated_at: 2026-03-07T21:54:42Z
---

Replace all us.awaits.chaos reverse domain references with me.byjp.cosyposts throughout the project. This includes:
- iOS bundle identifiers (us.awaits.chaos.app → me.byjp.cosyposts.app, us.awaits.chaos.app.share → me.byjp.cosyposts.app.share)
- App Group identifier (group.us.awaits.chaos → group.me.byjp.cosyposts)
- Entitlements files
- project.yml bundleIdPrefix
- Any other references in Swift source or config files
