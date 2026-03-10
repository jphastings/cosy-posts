---
# chaos-i0ev
title: Go API test suite
status: todo
type: epic
priority: high
created_at: 2026-03-10T21:35:47Z
updated_at: 2026-03-10T21:35:47Z
---

Minimum test suite to document and protect the Go API's core behaviors. Each test exists to catch a specific class of silent failure that would break the iOS app or compromise security.

The iOS app and Go API form a contract: the app uploads media via TUS, authenticates via magic links, and expects specific JSON responses. These tests encode that contract.

## Unit tests — pure functions, no I/O

### Content package (internal/content)

- [ ] **ParseFrontmatter extracts typed YAML and body from delimited content** — frontmatter is how every post stores its metadata; if the \`---\` delimiter parsing breaks, all posts render without dates, authors, or locations
- [ ] **ParseFrontmatter returns full text as body when no frontmatter delimiters exist** — the site info page (\`index.md\` in content root) may have no frontmatter; this must not panic or return empty
- [ ] **PreferredLang extracts primary subtag from Accept-Language** — locale-aware content serving depends on this; if \`es-MX\` doesn't yield \`es\`, Spanish speakers see English posts
- [ ] **PreferredLang returns empty string for missing or wildcard headers** — the fallback to default locale must trigger, not a zero-value match against \`""\` locale posts
- [ ] **ParseTranslationFilename identifies \`index.{lang}.{ext}\` and rejects non-translation files** — locale discovery walks the filesystem; false positives here would count media files as locales

### Post assembly helpers

- [ ] **extractTags finds unique lowercase hashtags from body text** — tags power the site's tag index; duplicates or case variants would create phantom tag pages
- [ ] **isValidLocale accepts 2-8 letter strings and rejects paths, numbers, empty** — this is a security boundary; a locale of \`../../../etc\` would write files outside the post directory
- [ ] **computeMediaAspectRatio clamps between 4:5 and 1.91:1** — the CSS grid uses this ratio; values outside the range cause layout overflow or collapsed cards on the site

### Auth helpers

- [ ] **emailInCSV matches case-insensitively and ignores trailing CSV columns** — the iOS app lowercases email before sending, but CSV files are hand-edited; \`Alice@Example.com\` in the CSV must match \`alice@example.com\` from the app
- [ ] **hexPattern rejects non-hex, wrong-length, and path traversal tokens** — tokens are used as filenames; \`../sessions/valid-id\` as a token would read a session file instead

### Photo processing

- [ ] **detectFormat identifies JPEG, PNG, and HEIC by magic bytes, not extension** — iOS names HEIC files \`.jpg\` sometimes; extension-based detection would send HEIC bytes to the JPEG decoder and crash
- [ ] **downscale preserves aspect ratio and is a no-op for images within bounds** — uploading a 1024x768 photo must not be upscaled; a 4032x3024 must become 2048xN with correct proportions
- [ ] **patchExifOrientation resets tag 0x0112 to 1 in both big-endian and little-endian TIFF** — after pixel rotation, the EXIF tag must say "normal" or viewers will double-rotate the image
- [ ] **applyOrientation handles all 8 EXIF orientation values correctly** — iPhone photos are orientation 6 (rotated 90° CW); if this transform is wrong, every portrait photo displays sideways

### Video probing

- [ ] **Probe extracts width and height from MP4/MOV stsd box** — the site grid needs video dimensions for aspect ratio; returning 0x0 causes division-by-zero in ratio calculation
- [ ] **Probe extracts GPS from Apple ©xyz atom in ISO 6709 format** — video geolocation is only available via this atom; if parsing fails, video posts never have location data even when the video has it

## Integration tests — HTTP handlers, filesystem, TUS protocol

### Auth flow (contract with iOS AuthManager)

- [ ] **POST /auth/send with authorized email returns 200 JSON \`{ok:true}\`** — the iOS app checks for 200 status and this exact JSON shape to show "check your email"; any deviation leaves the user on a spinner
- [ ] **POST /auth/send with unauthorized email still returns 200 JSON** — the server must not reveal whether an email is authorized (timing-safe); the iOS app shows the same "check email" screen either way
- [ ] **GET /auth/verify with valid token returns JSON \`{session, role, email}\`** — the iOS app destructures these three fields to establish its auth state; a missing field crashes the app
- [ ] **GET /auth/verify with expired/invalid token returns 401 JSON** — the iOS app shows a "link expired" message on 401; if the server returns 302 redirect instead, the app can't parse it
- [ ] **Bearer token in Authorization header authenticates requests** — the iOS TUS client sends \`Authorization: Bearer {session}\` on every upload; if the middleware doesn't extract it, all uploads fail with 401
- [ ] **Session expires after 180 days and returns 401** — the iOS app stores the session indefinitely; if the server silently accepts expired sessions, revocation is impossible

### TUS upload protocol (contract with iOS TUSClient)

- [ ] **POST /files/ with valid metadata returns 201 with Location header** — the iOS client reads \`Location\` to know where to PATCH; a missing header throws \`.missingLocation\` and the upload is unrecoverable
- [ ] **HEAD /files/{id} returns Upload-Offset for resume** — after app backgrounding or network loss, the client HEAD-queries to find where to resume; wrong offset means duplicate bytes or corruption
- [ ] **PATCH /files/{id} with correct offset returns 204 and new Upload-Offset** — each chunk upload must advance the offset; the client uses this to track progress and detect stalls
- [ ] **Unauthenticated upload requests return 401** — without this, anyone who discovers the /files/ endpoint can upload arbitrary content to the server

### Post assembly (contract: upload sequence → on-disk post)

- [ ] **Body upload with role=body triggers assembly and produces index file with correct frontmatter** — this is the core pipeline: the iOS app uploads body last, and the server must produce a valid post directory with date, locale, and tags in YAML frontmatter
- [ ] **Media uploads are copied to post directory and images are processed to JPEG** — the iOS app uploads HEIC/PNG originals; the server must normalize to JPEG for web display, and the files must end up alongside the index file
- [ ] **Locale body uploads produce separate index.{locale}.{ext} files** — the iOS compose view supports multiple language entries per post; each must become a separate file so the site renderer can serve the right language
- [ ] **Assembly cleans up TUS upload files after success** — without cleanup, the temp directory grows unbounded; each post leaves ~3 files per upload (data, .info, .lock)
- [ ] **Filename metadata is sanitized to prevent path traversal** — a malicious client sending \`filename: ../../etc/cron.d/evil\` must not write outside the post directory; \`filepath.Base\` must strip directory components

### API info endpoint (contract with iOS ServerSetupView)

- [ ] **GET /api/info returns JSON with name, version, stats, and locales** — the iOS app's server setup view fetches this to verify the server is reachable and display the community name; missing fields cause the setup to fail

### Post deletion

- [ ] **DELETE /api/posts/{id} removes post directory and returns 200** — the site's delete button calls this; if it silently fails, the post reappears on next page load
- [ ] **DELETE /api/posts/{id} with path traversal ID returns 400** — IDs like \`../\` or \`/etc\` must be rejected before any filesystem operation

### Site rendering (integration)

- [ ] **GET / renders HTML with all posts sorted by date descending** — this is the primary user-facing page; if post loading or sorting breaks, users see an empty or misordered feed
- [ ] **GET / with Accept-Language swaps post body to matching translation** — the site serves a multilingual community; if locale fallback breaks, everyone sees the original language regardless of their browser settings
- [ ] **GET /content/{path} serves media files and rejects path traversal** — media URLs are embedded in post HTML; the path check (\`strings.HasPrefix(abs, contentDir)\`) prevents serving \`/etc/passwd\` via crafted URLs
