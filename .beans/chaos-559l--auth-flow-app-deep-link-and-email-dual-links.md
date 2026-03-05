---
# chaos-559l
title: 'Auth flow: app deep link and email dual links'
status: completed
type: feature
priority: normal
created_at: 2026-03-05T00:20:19Z
updated_at: 2026-03-05T00:23:03Z
---

Update auth email to include two links (site + app). App deep link carries magic token, app calls /auth/verify to exchange for session. Update /auth/verify to return JSON for non-browser clients.

## Todo

- [x] Update magic link email to include two links: site login + app deep link
- [x] App deep link format: chaos://auth?token={token}&server={baseURL}
- [x] Update /auth/verify to return JSON session response for non-browser clients
- [x] Only show app link for post role users
- [x] Verify go build passes

## Summary of Changes

- Email includes two links for post-role users (site + app deep link)
- /auth/verify returns JSON {session, role} when Accept: application/json
- Middleware accepts both cookie and Authorization: Bearer header
- Deep link format: chaos://auth?token={token}&server={baseURL}
