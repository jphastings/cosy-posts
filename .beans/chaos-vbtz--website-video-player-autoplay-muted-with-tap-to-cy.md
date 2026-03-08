---
# chaos-vbtz
title: 'Website video player: autoplay muted with tap-to-cycle controls'
status: todo
type: feature
created_at: 2026-03-08T11:56:42Z
updated_at: 2026-03-08T11:56:42Z
---

Configure the website video player to remove the default browser control overlay and implement a custom three-state tap cycle.

## Behaviour

- Videos autoplay muted by default (if the browser allows autoplay)
- If autoplay is not permitted (no prior site interaction), videos start paused
- No browser control overlay (no play/pause/scrub/volume chrome)
- Tapping cycles through three states:
  1. **Paused** → Playing (muted)
  2. **Playing (muted)** → Playing (with sound)
  3. **Playing (with sound)** → Paused
- Visual indicator for current state (e.g. subtle icon overlay on tap)

## Tasks

- [ ] Remove default video controls
- [ ] Implement muted autoplay with paused fallback
- [ ] Add tap handler cycling through paused → muted → unmuted → paused
- [ ] Add visual feedback for state changes (transient icon overlay or similar)
