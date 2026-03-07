---
# chaos-y74n
title: Set up Apple Developer account & TestFlight CI
status: todo
type: task
priority: normal
created_at: 2026-03-07T22:21:44Z
updated_at: 2026-03-07T22:22:19Z
---

Get an Apple Developer account configured (if needed) and set up automation in this repo to publish the Cosy Posts iOS app to TestFlight.

## Tasks

- [ ] Create an Apple Developer account at developer.apple.com\n- [ ] Enroll in the Apple Developer Program ($99/year)
- [ ] Enroll in the Apple Developer Program ($99/year) if not already enrolled
- [ ] Create App ID and provisioning profiles for `me.byjp.cosyposts`
- [ ] Set up App Store Connect entry for the app
- [ ] Configure code signing (certificates & profiles)
- [ ] Set up GitHub Actions workflow for building and uploading to TestFlight
- [ ] Configure required secrets (API keys, certificates) in GitHub repo settings
- [ ] Test end-to-end: push triggers build, archive, and TestFlight upload
- [ ] Document the setup in the repo
