---
# chaos-c8k6
title: Add code coverage metrics
status: completed
type: task
priority: normal
created_at: 2026-03-20T15:40:37Z
updated_at: 2026-03-20T15:44:44Z
---

Add coverage collection for Go and Swift tests. Local CLI feedback via xc tasks, CI reporting via GitHub Job Summaries.

## Tasks

- [x] Add coverage artifacts to .gitignore
- [x] Add `test-api`, `test-app`, `test` xc tasks to README.md
- [x] Add coverage to `api` and `contract-provider` CI jobs
- [x] Add new `app` CI job with Swift coverage

## Summary of Changes

Added code coverage collection using native tooling only (no external services):
- `.gitignore`: coverage artifact patterns
- `README.md`: three new xc tasks (`test-api`, `test-app`, `test`) for local CLI coverage
- `.github/workflows/test.yaml`: `-coverprofile` on Go jobs, new `app` job for Swift UploadTests, Job Summaries on all
