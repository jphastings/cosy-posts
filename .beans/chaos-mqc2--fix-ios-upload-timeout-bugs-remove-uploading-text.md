---
# chaos-mqc2
title: 'Fix iOS upload: timeout bugs, remove Uploading text, cross-platform tests'
status: completed
type: bug
priority: normal
created_at: 2026-03-18T20:57:59Z
updated_at: 2026-03-18T21:26:05Z
---

Upload never completes on iOS due to broken withTimeout helper and missing URLSession timeouts. Also remove redundant Uploading text and make UploadTests run on both iOS and macOS.


## Summary of Changes

**UploadManager.swift:**
- Fixed broken `withTimeout` helper: used `TimeoutOutcome` enum + `group.next()` so the timeout actually enforces and operation-nil returns immediately (was waiting 60s or hanging forever)
- Fixed same bug in `exportViaTransferable` using local `Outcome` enum
- Added dedicated `URLSession` with 30s request / 5min resource timeouts (was using `.shared` with 7-day resource timeout, causing hangs on unreachable servers)
- Made `withTimeout` internal for testability

**ContentView.swift:**
- Removed redundant "Uploading..." text from bottom toolbar (spinner on Post button is sufficient)

**project.yml:**
- Made UploadTests cross-platform: `supportedDestinations: [iOS, macOS]`
- Added `TEST_HOST[sdk=macosx*]` override for correct macOS app bundle path

**UploadFlowTests.swift:**
- Added `hangMethod` to TUSMockProtocol/TUSRequestLog for simulating unresponsive servers
- `testUploadFailsOnServerError`: verifies post marked `.failed` on HTTP 500
- `testUploadCompletesOnServerTimeout`: verifies processQueue completes (not hangs) when server is unresponsive
- `testTimeoutReturnsImmediatelyOnOperationFailure`: verifies withTimeout returns instantly on nil (not 60s)
- `testTimeoutEnforcesDeadline`: verifies withTimeout cancels hanging operations
