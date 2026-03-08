---
# chaos-y74n
title: Set up Apple Developer account & TestFlight CI
status: completed
type: task
priority: normal
created_at: 2026-03-07T22:21:44Z
updated_at: 2026-03-08T10:36:42Z
---

Get an Apple Developer account configured (if needed) and set up automation in this repo to publish the Cosy Posts iOS app to TestFlight.

## Tasks

- [x] Create an Apple Developer account at developer.apple.com
- [x] Enroll in the Apple Developer Program ($99/year)
- [x] Create App ID and provisioning profiles for `me.byjp.cosyposts`
- [x] Set up App Store Connect entry for the app
- [x] Configure code signing (DEVELOPMENT_TEAM in project.yml)
- [x] Set up GitHub Actions workflow for building and uploading to TestFlight
- [x] Configure required secrets (API keys, certificates) in GitHub repo settings
- [x] Test end-to-end: push triggers build, archive, and TestFlight upload
- [x] Document the setup in the repo (workflow is self-documenting)

## Summary of Changes

- Added `.github/workflows/testflight.yaml` — archives without signing, then exports and uploads to TestFlight via App Store Connect API key
- Configured `project.yml` with DEVELOPMENT_TEAM and CODE_SIGN_STYLE
- Added placeholder app icon, iPad orientations, BGTaskSchedulerPermittedIdentifiers, and NSExtensionAttributes to fix App Store validation
- Runner: `macos-26` (Xcode 26.2)
- Triggers: `app/v*` tags or manual dispatch
- Secrets needed: `APP_STORE_CONNECT_API_KEY` (secret), `APP_STORE_CONNECT_KEY_ID` and `APP_STORE_CONNECT_ISSUER_ID` (vars)
