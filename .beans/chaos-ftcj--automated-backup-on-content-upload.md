---
# chaos-ftcj
title: Automated backup on content upload
status: todo
type: feature
created_at: 2026-03-06T21:39:26Z
updated_at: 2026-03-06T21:39:26Z
---

Allow configuration of automatic backup when new content is uploaded. Support multiple backup destinations, potentially including:

- Google Drive
- iCloud Drive (if feasible)
- SSH/SCP/rsync to a remote server
- S3-compatible storage (e.g. Cloudflare R2, AWS S3, Backblaze B2)

Config should allow one or more destinations. Backup triggered on new content upload.
