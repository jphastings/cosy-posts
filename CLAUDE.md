# chaos.awaits.us

Private community platform for video/photo/audio/text sharing.

## Architecture

Monorepo with two main components:

- `api/` — Go HTTP API server with TUS resumable uploads, photo processing, post assembly
- `app/` — SwiftUI iOS 26 app for uploading media + text

## API Server (`api/`)

**Language**: Go (single binary, YAML config file argument)

**Key libraries**:
- `github.com/tus/tusd/v2` — TUS resumable upload server
- `github.com/gen2brain/jpegli` — JPEG encoding via jpegli
- `golang.org/x/image` — Image processing
- `gopkg.in/yaml.v3` — YAML config and frontmatter

**Upload protocol**: TUS (tus.io) resumable uploads. Each upload has `post-id` metadata (nanoid, generated client-side). Media files uploaded first, text body uploaded last. Body upload completion triggers post assembly.

**Photo processing**: Downscale to max 2048px on either side, encode with jpegli. Input: HEIC, JPEG, PNG.

**Post directory structure**: `{content_dir}/YYYY/MM/DD/{nanoid}/`
- `index.md` or `index.djot` — Text content with YAML frontmatter
- Media files alongside

**Frontmatter fields**: `date` (ISO 8601, declared by uploader), `location` (`lat`/`lng` from first media with EXIF GPS), `tags` (array of #hashtags extracted from body text)

**Site rebuild**: Configurable shell command, exec'd as subprocess, stdout/stderr piped to configured log file. Non-blocking.

**Auth**: Skipped for now.

## iOS App (`app/`)

**Target**: iOS 26, SwiftUI

**Main view**: Single view with PHPicker for photos/videos, swipeable preview with remove, text input, upload button.

**Upload system**: TUS protocol, nanoid generated per post, media uploaded first then text body last. Persistent queue (SwiftData). Offline-first: queue when offline, send when online. Network monitoring.

**Share sheet extension**: Receives shared media from other apps, simplified UI with text input, saves to shared App Group container for main app queue.

## Conventions

- Use beans (not TodoWrite) for all work tracking
- Commit per bean completion — each commit contains only that bean's work
- Include bean files in commits
- No auth implementation yet
- Site rebuild command is configurable; use `echo 'rebuild site'` as placeholder

## Commands

```bash
# Run API server
cd api && go run . -config config.yaml

# Beans
beans list --ready          # See what to work on
beans show <id>             # View bean details
```
