---
# chaos-0mfv
title: API server security & code quality fixes
status: completed
type: epic
priority: normal
created_at: 2026-03-10T18:49:40Z
updated_at: 2026-03-10T19:03:29Z
---

Security and code quality improvements identified by bar-raiser review of the Go API server.

## Security (Critical)
- [x] Sanitize TUS `filename` metadata with `filepath.Base` in `post/assemble.go`; validate `locale` against `^[a-z]{2,8}$` and `content-ext` against `{md, djot}`
- [x] Validate `token`/`sessionID` against `^[0-9a-f]{64}$` in `auth/auth.go` before filesystem path construction
- [x] Escape `name` with `html.EscapeString` (or use `html/template`) in login page to prevent XSS via `Host` header
- [x] Replace `http.ListenAndServe` with explicit `http.Server` with `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`
- [x] Acquire `csvMu` and check `emailInCSV` before appending to `wants-account.csv`

## Bugs
- [x] Fix `CAN_POST_CSV` in `rebuild/rebuild.go` to use `cfg.AuthDir` instead of `cfg.Dir`
- [x] Remove `defer out.Close()` in `copyFile` (`post/assemble.go`) — keep only the explicit `return out.Close()`
- [x] Change `Cache-Control` on auth-gated home page from `public` to `private` in `site/site.go`

## Code Quality
- [x] Extract duplicated `parseTranslationFilename`, `loadSiteInfo`, and `videoExts` from `info/` and `site/` into a shared package
- [x] Delete unnecessary `decodeHEIC` wrapper in `photo/process.go`
- [x] Handle `binary.Write` return value in `photo/process.go`


## Summary of Changes

All security, bug, and code quality issues resolved:
- Path traversal fixes: filename sanitized with filepath.Base, locale/content-ext validated
- Auth hardened: token/session IDs validated against hex pattern, XSS prevented with html.EscapeString
- HTTP server timeouts added, wants-account.csv deduplication with mutex
- rebuild.go uses cfg.AuthDir, copyFile double-close fixed, Cache-Control set to private
- Extracted shared internal/content package for duplicated code (ParseTranslationFilename, ParseFrontmatter, PreferredLang, VideoExts/ImageExts/MediaExts)
