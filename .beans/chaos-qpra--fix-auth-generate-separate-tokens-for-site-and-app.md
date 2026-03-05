---
# chaos-qpra
title: 'Fix auth: generate separate tokens for site and app login links'
status: completed
type: bug
priority: normal
created_at: 2026-03-05T00:38:56Z
updated_at: 2026-03-05T07:05:26Z
---

Both site and app login links in the magic link email share the same single-use token. Whichever is clicked first consumes the token, making the other fail. Also investigate upload completion issue.

## Summary of Changes

### API (api/auth/auth.go)
- Generate **two separate tokens** for post-role users: one for the site link, one for the app deep link
- Updated `sendMagicLink` signature to accept `siteToken` and `appToken` separately
- Added logging to middleware for auth rejections (method, path, reason)

### iOS App
- Added `loginError` property to `AuthManager` — set when deep link token exchange fails
- `handleDeepLink` now shows descriptive error messages for used/expired tokens and connection failures
- `LoginView` displays a red error banner above the login web view when `loginError` is set

### Root Cause
ATS (App Transport Security) was blocking TUS PATCH requests. Adding `NSAllowsArbitraryLoads` to Info.plist fixed it.

### Additional Changes
- Added `os.Logger` to TUSClient and UploadManager for debugging
- User has reverse proxy adding SSL: `https://chaos.awaits.us.test/` → `127.0.0.1:8080`
