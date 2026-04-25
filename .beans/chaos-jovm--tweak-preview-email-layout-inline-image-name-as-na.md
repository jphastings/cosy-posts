---
# chaos-jovm
title: 'Tweak preview email layout: inline image, name as ''Name:'' prefix, linked Continue reading'
status: completed
type: task
priority: normal
created_at: 2026-04-25T10:15:45Z
updated_at: 2026-04-25T10:39:54Z
---

Follow-up to chaos-pcqc based on first received preview email.

## Tasks
- [x] Switch to per-recipient client.Emails.Send when preview is on (Resend Batch silently drops attachments) so the inline image actually arrives
- [x] Change per-post layout to '**Name:** body excerpt… [Continue reading on the site →]' on a single line, with the link replacing the bottom 'Visit the site' CTA
- [x] Remove the now-unused NotifyPostHeader i18n key from en/es/es-VE/fr locale files

## Summary of Changes

- `api/notify/scheduler.go`: Split the send path. Plain notifications still go via `client.Batch.Send` (efficient, no attachments needed). Preview notifications now go per-recipient via `client.Emails.Send` because Resend's batch endpoint silently drops attachments — confirmed by the first received preview email arriving as `multipart/alternative` with no image part. Pre-built `[]preview` chunks are computed once (image bytes read once into shared `*resend.Attachment` slice) and the recipient loop only swaps in the magic link.
- Per-post HTML now renders as `<hr><img><p><strong>Name:</strong> excerpt… <a>Continue reading on the site →</a></p>`. The bottom standalone “Visit the site” CTA is gone in preview mode; the per-post `Continue reading` link replaces it.
- Dropped the now-unused `NotifyPostHeader` i18n key from all four locale files.
- `magicLink` extracted as a small helper since both send paths need it.

`go build ./...`, `go test ./notify/...`, `go test -tags pact -run TestPactProvider ./...` all pass.
