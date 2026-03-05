---
# chaos-kgve
title: Email magic link authentication
status: completed
type: feature
priority: normal
created_at: 2026-03-04T23:34:32Z
updated_at: 2026-03-04T23:46:45Z
---

Build email-based magic link auth middleware for the Go API server. Filesystem-based token/session storage, Resend for email delivery.

## Todo

- [x] Add auth config fields to config.go
- [x] Create api/auth/auth.go (storage, handlers, middleware)
- [x] Update main.go to register auth routes and wrap with middleware
- [x] Add resend-go dependency
- [x] Update config.yaml with placeholder auth values
- [x] Verify go build passes

## Summary of Changes

- New `api/auth/auth.go`: filesystem token/session storage, CSV-based authorization (can-view.csv, can-post.csv, wants-account.csv), login page, magic link send/verify handlers, role-aware middleware
- Updated `api/config/config.go`: added ResendAPIKey, BaseURL, AuthDir, FromEmail fields
- Updated `api/main.go`: registered auth routes, wrapped mux with auth middleware
- Updated `api/config.yaml`: added placeholder auth config values
- Added `github.com/resend/resend-go/v2` dependency
