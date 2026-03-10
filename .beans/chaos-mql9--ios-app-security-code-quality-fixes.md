---
# chaos-mql9
title: iOS app security & code quality fixes
status: todo
type: epic
created_at: 2026-03-10T18:49:41Z
updated_at: 2026-03-10T18:49:41Z
---

Security and code quality improvements identified by bar-raiser review of the iOS app.

## Security
- [ ] Move session token from `UserDefaults` to Keychain in `AuthManager`

## Bugs
- [ ] Wrap `PHImageManager` callback continuations with `withTaskCancellationHandler` to resume on cancellation (`exportViaImageData`, `exportViaRequestImage`, `exportVideo`)
- [ ] Fix `if let _ = try?` on `Void`-returning `FileManager.copyItem` in `UploadManager.importSharedPosts` — use `do/catch` with logging
- [ ] Catch `saveToContainer` errors in `ShareViewController.postTapped` and show an alert instead of silently losing the post
- [ ] Clear `errorMessage` in `ComposeViewModel.reset()`

## Code Quality
- [ ] Extract duplicated `Nanoid` implementation into a shared file accessible to both app and share extension targets
- [ ] Extract duplicated `SharedPost`/`SharedPostManifest` structs into a shared file
- [ ] Store `Task` handle in `ComposeViewModel.upload()` and cancel on view disappear
- [ ] Move `NotificationCenter.post` out of `TUSError.server()` factory — handle 401 at the call site in `UploadManager`
- [ ] Replace `withThrowingTaskGroup` timeout in `exportViaTransferable` with existing `withTimeout` helper
- [ ] Extract shared media item view from `MediaCarouselView` to eliminate `singleItem`/`multiItem` duplication
