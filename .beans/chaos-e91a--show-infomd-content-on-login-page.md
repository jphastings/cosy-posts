---
# chaos-e91a
title: Show info.md content on login page
status: completed
type: feature
priority: normal
created_at: 2026-04-25T09:50:55Z
updated_at: 2026-04-25T09:55:06Z
---

Allow operators to drop a `login.md` (or `login.<lang>.md`) into the root of `content_dir` and have its rendered Markdown appear on `/auth/login` between the title and the email input, using the visitor's Accept-Language preference.

Mirrors the existing `index.md` / `index.<lang>.md` pattern used by `/api/info/site` (`api/info/info.go:loadSiteInfo`).

## Tasks
- [x] Extract `LoadLocalizedMarkdown(dir, base, prefLang)` helper in `api/internal/content/content.go` (factor out logic from `info.loadSiteInfo`)
- [x] Replace body of `info.loadSiteInfo` with a call to the new helper
- [x] Add `{{info}}` placeholder to `loginFormHTML` between `<h1>` and `<form>`
- [x] Add `.info` CSS rules (light + dark) to login form styles
- [x] In `LoginPage` handler, call helper with `cfg.ContentDir` + `"info"` + `lang`; wrap non-empty result in `<div class="info">…</div>`, otherwise empty string
- [x] `go build ./...` and `go test ./...` pass (incl. `go test -tags pact -run TestPactProvider`)
- [x] Manual verify: no file → unchanged; `info.md` → renders; `info.fr.md` with `Accept-Language: fr` → French; `.djot` also works

## Plan
See `/Users/jp/.claude/plans/can-you-please-update-elegant-waffle.md`

## Summary of Changes

- Added `content.LoadLocalizedMarkdown(dir, base, prefLang)` to `api/internal/content/content.go` — generic helper that tries `{dir}/{base}.{lang}.{md|djot}` then falls back to `{dir}/{base}.{md|djot}`, returning rendered HTML or empty string.
- Collapsed `info.loadSiteInfo` body to a single call to the new helper (no behaviour change).
- `LoginPage` handler now reads `info.md` / `info.<lang>.md` from `cfg.ContentDir` using the visitor’s `Accept-Language`, wraps the rendered HTML in `<div class="info">…</div>`, and substitutes it into the new `{{info}}` placeholder. When no file exists the placeholder collapses to empty and the page is unchanged.
- Added `.info` CSS (subtle muted text, left-aligned, 24px bottom margin, paragraph spacing, inherited link colour) — works in both light and dark colour schemes.
- Verified end-to-end with an in-process `httptest` driver covering: no file, `info.md` (English), `info.fr.md` (French), and `.djot` fallback. All `go build`, `go test ./...`, and `go test -tags pact -run TestPactProvider` pass.
