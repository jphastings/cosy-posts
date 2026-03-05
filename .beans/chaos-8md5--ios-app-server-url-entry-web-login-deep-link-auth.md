---
# chaos-8md5
title: 'iOS app: server URL entry, web login, deep link auth'
status: completed
type: feature
priority: normal
created_at: 2026-03-05T00:20:19Z
updated_at: 2026-03-05T00:26:31Z
blocked_by:
    - chaos-559l
---

Add server URL entry screen, web-based login flow, chaos:// deep link handler for auth token, session storage for TUS uploads.

## Todo

- [x] Add server URL entry screen (shown if no URL stored)
- [x] Store server URL in UserDefaults/AppStorage
- [x] Open web login page in-app when not authenticated
- [x] Register chaos:// URL scheme in Info.plist
- [x] Handle deep link: extract token, call /auth/verify, store session
- [x] Pass session via Bearer auth header with TUS upload requests
- [x] Show existing compose screen once authenticated

## Summary of Changes

- New AuthManager: stores server URL + session token in UserDefaults, handles chaos:// deep links
- New ServerSetupView: enter server URL when not configured
- New LoginView: WKWebView showing server login page
- Updated TUSClient: Bearer auth header on all requests
- Updated UploadManager: configure() method to sync auth state
- Updated ChaosAwaitsApp: RootView routes between setup/login/compose, onOpenURL handler
- Registered chaos:// URL scheme in Info.plist
