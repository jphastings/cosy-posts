---
# chaos-8md5
title: 'iOS app: server URL entry, web login, deep link auth'
status: todo
type: feature
priority: normal
created_at: 2026-03-05T00:20:19Z
updated_at: 2026-03-05T00:20:28Z
blocked_by:
    - chaos-559l
---

Add server URL entry screen, web-based login flow, chaos:// deep link handler for auth token, session storage for TUS uploads.

## Todo

- [ ] Add server URL entry screen (shown if no URL stored)
- [ ] Store server URL in UserDefaults/AppStorage
- [ ] Open web login page in-app when not authenticated
- [ ] Register chaos:// URL scheme in Info.plist
- [ ] Handle deep link: extract token, call /auth/verify, store session cookie
- [ ] Pass session cookie with TUS upload requests
- [ ] Show existing compose screen once authenticated
