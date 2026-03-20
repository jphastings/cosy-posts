---
# chaos-ep4o
title: Synchronous post assembly + client-side failure reporting
status: completed
type: bug
priority: normal
created_at: 2026-03-20T07:56:18Z
updated_at: 2026-03-20T08:00:36Z
---

Posted! toast shows even when server assembly fails. Fix by using tusd PreFinishResponseCallback for synchronous assembly, add Unwrap() to relativeLocationWriter, and propagate upload failures to the compose view.

## Tasks

- [x] Add `Unwrap()` to `relativeLocationWriter` in handler.go
- [x] Switch `NotifyCompleteUploads` to `PreFinishResponseCallback` in handler.go
- [x] Change `CompletionFunc` signature to return error
- [x] Update `server.go` onBodyDone to return assembly error
- [x] Remove async `listenForCompleted` goroutine
- [x] In UploadManager.swift, propagate post failure from `enqueuePost()`
- [x] Test Go API builds
- [x] Test Swift app builds


## Summary of Changes

**api/upload/handler.go:** Replaced async `NotifyCompleteUploads` + `listenForCompleted` goroutine with synchronous `PreFinishResponseCallback`. Assembly now runs before the TUS response is sent — if it fails, the client gets an error instead of 204. Added `Unwrap()` to `relativeLocationWriter` so tusd can set connection deadlines. Changed `CompletionFunc` to return `error`.

**api/server.go:** Updated `onBodyDone` to return assembly errors instead of just logging them.

**app/Sources/CosyPostsAdmin/UploadManager.swift:** After `processQueue()`, re-fetches the post to check if it was marked failed. If so, throws `UploadError.serverRejected` so the compose view shows an error instead of the success toast. Added `UploadError` enum.
