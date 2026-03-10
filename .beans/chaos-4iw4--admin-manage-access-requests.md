---
# chaos-4iw4
title: 'Admin: manage access requests'
status: completed
type: feature
priority: normal
created_at: 2026-03-06T21:33:14Z
updated_at: 2026-03-10T07:48:09Z
---

Allow management of people who've requested access to the site in the admin app. Needs an API endpoint for moving a person from the 'wants-account' list to the 'can-view' list.

## Tasks

- [x] Add API endpoint: GET /api/access-requests (list wants-account.csv entries)
- [x] Add API endpoint: POST /api/access-requests/{email}/approve (move from wants-account to can-view)
- [x] Add API endpoint: DELETE /api/access-requests/{email} (remove from wants-account)
- [x] Add AccessRequestManager in iOS app to call these endpoints
- [x] Add UI in iOS app to view and approve/deny access requests


## Summary of Changes

### API (Go)
- New `api/auth/access.go` with helpers: `readCSVEmails` (deduplicated list), `removeFromCSV` (rewrite without matching lines)
- `GET /api/access-requests` — lists deduplicated emails from wants-account.csv
- `POST /api/access-requests/{email}/approve` — moves email to can-view.csv
- `DELETE /api/access-requests/{email}` — removes email from wants-account.csv
- All endpoints require "post" role

### iOS App
- New `AccessRequestsView.swift` with `AccessRequestsLoader` (Observable) and approve/deny UI
- Integrated into `SiteInfoSheet` — shows pending requests with checkmark/X buttons
- Approve adds to can-view; deny just removes from wants-account
