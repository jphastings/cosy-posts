---
# chaos-5u83
title: Embedded default site in Go API server
status: completed
type: feature
priority: normal
created_at: 2026-03-06T16:34:51Z
updated_at: 2026-03-06T16:45:48Z
---

Embed the site templates, CSS, JS, and SVGs into the Go binary using go:embed. Use html/template + goldmark for rendering. When no build_command is configured, serve the site directly from the API server without needing an external build tool.

## Summary of Changes

Embedded the site directly into the Go API server binary using `go:embed`. When no `build_command` is configured, the server renders the site dynamically using Go's `html/template` + goldmark for markdown.

### New files
- `api/site/site.go` — HTTP handler that walks content dir, parses frontmatter, renders markdown, serves embedded CSS/SVG/templates
- `api/site/embed.go` — `go:embed` directives for static assets and templates  
- `api/site/static/` — Copied CSS and SVG assets for embedding
- `api/site/templates/` — Go HTML templates (base, home, single, post-card)

### Modified files
- `api/main.go` — Routes to embedded site handler when no build_command set, falls back to static file server when external build configured
- `api/go.mod` — Added `github.com/yuin/goldmark` dependency

### Behavior
- `build_command` set → external build system + static file serving (existing behavior)
- `build_command` empty → built-in renderer, zero external dependencies, single binary
