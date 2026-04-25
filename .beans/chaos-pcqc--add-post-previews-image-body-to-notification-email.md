---
# chaos-pcqc
title: Add post previews (image + body) to notification emails
status: completed
type: feature
priority: normal
created_at: 2026-04-25T09:58:41Z
updated_at: 2026-04-25T10:03:01Z
---

When email.send_post_preview is enabled (default false), include the first image and a truncated body excerpt for each new post in the notification email, with a clear cue that there's more to read on the site. Single magic link stays.

## Tasks
- [x] Add email.send_post_preview bool config (default false) with COSY_EMAIL_SEND_POST_PREVIEW env binding
- [x] Extend notify postInfo with dir/body/firstImg fields, populate during findPostsInWindow
- [x] Branch tick() on cfg.SendPostPreview(): preview-mode HTML with inline image (cid:) + truncated excerpt + 'continue reading' cue
- [x] Build inline attachments per post (resend.Attachment with ContentId), reuse across recipients
- [x] Add NotifyContinueReading and NotifyPostHeader i18n strings (en/es/es-VE/fr)
- [x] Verify go build ./... and contract tests pass

## Summary of Changes

- `api/config/config.go`: Added `Email.SendPostPreview` bool (mapstructure `send_post_preview`), default `false`, env `COSY_EMAIL_SEND_POST_PREVIEW`, accessor `SendPostPreview()`.
- `api/notify/scheduler.go`: Extended `postInfo` with `postID`, `dir`, `body`, `firstImg`. `findPostsInWindow` now records the body (already returned by `content.ParseFrontmatter`) and the first image in the post directory (alphabetical, filtered by `content.ImageExts`). `tick()` branches on `cfg.SendPostPreview()`: when on, builds preview HTML (per-post header, inline `<img src="cid:{nanoid}">`, ~280-char word-boundary excerpt, “continue reading” cue) plus `*resend.Attachment` slice (with `ContentId`) reused across recipients. When off, behaviour unchanged.
- `api/internal/i18n/locales/active.{en,es,es-VE,fr}.toml`: Added `NotifyPostHeader` and `NotifyContinueReading` messages.

Verified with `go build ./...`, `go test ./notify/...`, and `go test -tags pact -run TestPactProvider ./...` — all pass.
