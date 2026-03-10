---
# chaos-iqlx
title: Site renderer interaction & integration test suite
status: todo
type: epic
priority: normal
created_at: 2026-03-10T21:45:03Z
updated_at: 2026-03-10T21:47:48Z
---

Minimum set of tests to document WHY the site renderer behaves the way it does. Covers Go-testable template/data logic and browser-testable interaction behaviors.

## Test Sub-tasks

### Go-testable (unit/integration)

- [ ] **Post loading respects date-based directory structure** — Posts live in `YYYY/MM/DD/{nanoid}/` directories so the site can efficiently walk the filesystem chronologically. Test that `loadPosts` discovers posts nested in this structure and ignores files outside it.

- [ ] **Site-level index.md is excluded from post listing** — The content root can have its own `index.md` for site info (rendered separately). Test that it's never treated as a post, even though it matches the same filename pattern.

- [ ] **Posts sort newest-first** — Visitors see recent activity first; chronological order is the core UX. Test that `loadPosts` returns posts sorted by descending date.

- [ ] **Frontmatter drives post metadata** — Date, author, locale, and aspect ratio come from YAML frontmatter, not filenames or directory names. Test that `parsePost` correctly extracts all frontmatter fields and maps them to the Post struct.

- [ ] **Media files are discovered as siblings of index.md** — Media lives alongside the index file (no subdirectories) so the filesystem is the source of truth. Test that all recognized media extensions are found and non-media files are ignored.

- [ ] **Media aspect ratio falls back to image dimensions** — When frontmatter doesn't specify `media_aspect_ratio`, the site computes it from actual image dimensions (clamped 4:5 to 1.91:1). Test both the frontmatter-present and fallback-computed paths.

- [ ] **Video dimensions are probed for aspect ratio** — Videos can't use `image.DecodeConfig`, so we shell out to probe dimensions. Test that video width/height contribute to the average aspect ratio calculation.

- [ ] **Accept-Language selects translation files** — Posts can have `index.{lang}.md` translations. The site swaps in the translated body when the browser's preferred language matches. Test that the correct translation is loaded and that missing translations fall back to the default.

- [ ] **Site info respects locale fallback chain** — `loadSiteInfo` tries locale-specific `index.{lang}.md` first, then falls back to `index.md`. Test the full fallback chain including "no site info at all."

- [ ] **Markdown body renders to HTML** — Post bodies are stored as markdown but served as HTML. Test that goldmark rendering is applied and the result is embedded in the Post struct.

- [ ] **Author name resolved from members CSV** — The frontmatter stores an email address; the display name comes from `can-post.csv`. Test that known authors get display names and unknown authors show empty.

- [ ] **Content URLs are path-safe** — Media URLs are constructed from `filepath.Rel` + `filepath.ToSlash`. Test that the URL construction produces correct `/content/YYYY/MM/DD/{id}/filename` paths.

- [ ] **Content serving rejects path traversal** — The `/content/` handler resolves paths and checks they're under `contentDir`. Test that `../` sequences and symlinks outside the content root return 404.

- [ ] **Static assets are cache-immutable** — CSS and SVG assets are embedded and versioned with deploys, so they get long cache headers. Test that `/css/style.css` and `/img/*.svg` responses include appropriate `Cache-Control` headers.

- [ ] **Home page is privately cached** — The home page is behind auth, so it must use `Cache-Control: private`. Test that the home page response has `private` caching and `Vary: Accept-Language`.

### Browser-testable (interaction tests, deferred)

- [ ] **Carousel advances through media items** — Multiple media items in a post should be swipeable/navigable. Document the expected carousel behavior for future browser testing.

- [ ] **Video player has mute/unmute and pause controls** — Videos autoplay muted; users can unmute and pause. Document the expected interaction states.

- [ ] **Bookmark toggle persists in localStorage** — Bookmarking is client-side only (no server state). Document the expected localStorage key structure and toggle behavior.

- [ ] **Contact preference dialog shows member methods** — The info button reveals contact methods (WhatsApp, Signal, email) parsed from CSV. Document the expected dialog content.

- [ ] **Delete button only visible to authorized users** — `CanDelete` is set server-side based on role. Document the expected visibility logic.
