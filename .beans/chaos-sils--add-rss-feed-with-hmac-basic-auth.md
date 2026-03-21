---
# chaos-sils
title: Add RSS feed with HMAC basic auth
status: completed
type: feature
priority: normal
created_at: 2026-03-21T22:53:58Z
updated_at: 2026-03-21T22:57:22Z
---

Add /feed.xml endpoint with basic auth (username=email, password=HMAC-SHA256). Protected by can-view/can-post authorization lists. RSS 2.0 with full post content and media.

## Tasks

- [x] Add `rss_secret` config field
- [x] Export `LookupRole` from auth package
- [x] Add `/feed.xml` to auth middleware public paths
- [x] Create `api/feed/` package with RSS handler
- [x] Wire route in `server.go`
- [x] Test locally

## Summary of Changes

Added /feed.xml RSS 2.0 endpoint with HMAC-SHA256 basic auth:
- api/config: rss_secret config field + env var binding
- api/auth: Exported LookupRole, added /feed.xml to public routes
- api/feed: New package with RSS generation, HMAC auth, post loading
- api/server.go: Wired GET /feed.xml route

Feed is opt-in (only served when rss_secret is configured). Username=email, password=hex(HMAC-SHA256(email, rss_secret)). Access requires can-view or can-post.
