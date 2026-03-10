---
# chaos-p4h8
title: CI/CD improvements
status: todo
type: epic
created_at: 2026-03-10T18:49:44Z
updated_at: 2026-03-10T18:49:44Z
---

CI/CD improvements identified by bar-raiser review of GitHub Actions workflows and build config.

## Critical
- [ ] Fix Archive/Export signing contradiction in `testflight.yaml` — remove `CODE_SIGNING_REQUIRED=NO` / `CODE_SIGNING_ALLOWED=NO` or restructure signing
- [ ] Add `permissions: {}` to `testflight.yaml`

## Missing Checks
- [ ] Add CI workflow for `go test ./...` and `go vet ./...` on push/PR to `main`
- [ ] Add CI workflow to build iOS app on push/PR (xcodegen + xcodebuild for simulator)

## Quality
- [ ] Add guard against `VERSION=0.0.0` on `workflow_dispatch`, or add a version input parameter
- [ ] Pin xcodegen to a specific version in `testflight.yaml`
- [ ] Add `if: always()` cleanup step to delete API key from `~/private_keys/`
- [ ] Update stale "11ty-compatible" reference in README
- [ ] Remove boilerplate comments from `.goreleaser.yaml`
- [ ] Rename `GH_TOKEN` secret to `HOMEBREW_TAP_TOKEN` for clarity
