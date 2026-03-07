---
# chaos-m8at
title: Support audio upload in API
status: todo
type: feature
created_at: 2026-03-07T22:24:55Z
updated_at: 2026-03-07T22:24:55Z
---

Add support for audio file uploads (e.g. m4a, mp3, wav) through the TUS upload pipeline. The API should accept audio content types, store audio files alongside other media in the post directory, and include them in post assembly.

## Tasks

- [ ] Accept audio MIME types in upload handler
- [ ] Store audio files in post directory during assembly
- [ ] Include audio references in post frontmatter/content
