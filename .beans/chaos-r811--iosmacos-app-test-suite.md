---
# chaos-r811
title: iOS/macOS app test suite
status: todo
type: epic
priority: normal
created_at: 2026-03-10T21:46:26Z
updated_at: 2026-03-10T21:47:45Z
---

Minimum set of unit, integration, and contract tests to document WHY the iOS/macOS app behaves the way it does. Covers Swift-testable logic, TUS protocol contract (matching Go API expectations), and critical silent-failure modes.

## Test Sub-tasks

### Unit Tests

- [ ] **Nanoid generates URL-safe IDs of correct length** — Post IDs are nanoids (`0-9a-z`, 21 chars) generated client-side and used as directory names on the server. Test alphabet constraint, length, and uniqueness across multiple generations.

- [ ] **ComposeViewModel enforces at least one media item** — You can't create a post without media (text-only posts aren't the use case). Test that the upload button is disabled when media is empty and enabled when media is added.

- [ ] **ComposeViewModel extracts creation date from first photo** — The post date comes from the first photo's EXIF/metadata, not the upload time, so posts reflect when moments happened. Test that `creationDate` is extracted from PHAsset metadata and formatted as ISO 8601.

- [ ] **PendingPost serializes for offline persistence** — Posts queue locally (SwiftData) and survive app restarts. Test that PendingPost round-trips through encoding/decoding with all fields intact, including media references.

- [ ] **MediaItem normalizes file extensions** — The server uses extensions to detect format (HEIC→process, JPEG→process, MP4→copy). Test that MediaItem produces the correct extension for each PHAsset media type and subtype.

- [ ] **MediaItem supports drag-and-drop reordering** — Users arrange media order before posting; order determines which photo's EXIF sets the post date. Test that Transferable conformance produces valid item providers and that the drag/drop data round-trips.

- [ ] **TranslationManager detects non-primary locale** — Auto-translation triggers when the post text isn't in the post's primary locale. Test locale detection logic and that translation is skipped when text matches the primary locale.

- [ ] **NetworkMonitor reflects connectivity state** — Upload queue pauses when offline and resumes when online. Test that the monitor correctly reports connected/disconnected states (mock NWPathMonitor).

### Integration Tests

- [ ] **TUSClient creates upload with correct metadata encoding** — TUS metadata uses base64-encoded values with comma-separated key-value pairs. Test that the client produces headers matching the TUS spec (`Upload-Metadata: key base64val, key2 base64val2`).

- [ ] **TUSClient resumes interrupted uploads via HEAD** — Resumability is the entire point of TUS. Test that after a simulated interruption, the client sends HEAD to get the current offset, then PATCH from that offset (not from zero).

- [ ] **TUSClient uploads body last to trigger assembly** — The Go API assembles the post when the body upload completes. If body arrives before media, media is lost. Test that media uploads all complete before the body upload begins.

- [ ] **UploadManager tries PHAsset export before falling back** — Three export strategies exist (asset export → resource copy → thumbnail fallback) because iCloud-optimized photos may not have local data. Test the fallback chain: first strategy fails → second tried → third tried → error only if all fail.

- [ ] **UploadManager handles iCloud-deferred photos gracefully** — When "Optimize Mac Storage" is on, full-size data isn't local. Test that the manager doesn't crash or hang, and that it falls back to a degraded export path.

- [ ] **AuthManager stores session token securely after magic link** — The magic link flow exchanges a token for a session. Test that the session token is persisted (Keychain/UserDefaults) and subsequent API calls include it.

- [ ] **Share extension writes inbox format main app can read** — The share extension saves to `inbox/{postID}/post.json` in the shared App Group container. Test that the JSON schema matches what the main app's queue reader expects.

### Contract Tests (app ↔ API)

These mirror the Go-side contract tests in `chaos-i0ev` — together they verify the TUS protocol contract without requiring a running server.

- [ ] **Upload-Metadata header matches Go parser expectations** — The Go API reads `post-id`, `filename`, `content-type`, `role`, `date`, `content-ext` from TUS metadata. Test that the Swift TUSClient produces these exact keys with correct base64 encoding that the Go side can decode.

- [ ] **Body upload metadata signals assembly trigger** — The Go API triggers post assembly when it sees `role: body` in upload metadata. Test that the Swift client sets `role=body` on the text upload and `role` is absent (or different) on media uploads.

- [ ] **Date format matches Go time.Parse expectations** — The Go API tries `time.RFC3339` then `2006-01-02`. Test that the Swift client's date formatting produces strings that match one of these formats.

- [ ] **Content-ext values match Go allowlist** — The Go API only accepts `md` or `djot`. Test that the Swift client only ever sends one of these values.

### Silent Failure Modes (regression tests)

- [ ] **Large video upload doesn't timeout** — Videos can be hundreds of MB; TUS chunking must handle slow uploads without the connection being dropped. Test that the client sends appropriate chunk sizes and handles partial responses.

- [ ] **Concurrent uploads for same post-id don't race** — Multiple media files upload in parallel for one post. Test that the TUSClient actor serializes state mutations while allowing concurrent network I/O.

- [ ] **App backgrounding doesn't lose queued posts** — SwiftData persistence must flush before the app suspends. Test that a post added to the queue survives a simulated app lifecycle (active → background → terminated → launch).
