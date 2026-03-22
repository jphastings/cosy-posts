---
# chaos-9ybp
title: Email notifications for new posts
status: completed
type: feature
priority: normal
created_at: 2026-03-22T17:25:10Z
updated_at: 2026-03-22T17:37:19Z
---

Background scheduler sends email notifications to subscribers when new posts appear. Runs every N minutes, scans for posts in a time window, sends batch emails via Resend with magic link tokens.

## Tasks

- [x] Add `site.url` and `email_window_minutes` to config
- [x] Export `CreateToken` from auth package
- [x] Add scheduler to notify package
- [x] Wire scheduler in main.go
- [x] Test locally
