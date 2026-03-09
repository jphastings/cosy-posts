---
# chaos-vbtz
title: 'Website video player: autoplay muted with tap-to-cycle controls'
status: completed
type: feature
priority: normal
created_at: 2026-03-08T11:56:42Z
updated_at: 2026-03-09T09:35:21Z
---

Configure the website video player to remove the default browser control overlay and implement a custom tap-to-play, tap-to-pause interface.

## Behaviour

- No browser control overlay (no play/pause/scrub/volume chrome)
- Videos autoplay muted by default when they are more on the page than off the page (if the browser allows autoplay)
- If autoplay is not permitted (no prior site interaction), videos remain paused as they scroll onto the screen, until they are tapped.
- The site starts with all videos being muted (with a 'muted' icon — `speaker-x-mark` from heroicons.com — in the bottom right corner  of the video), and tapping that icon switches to playing videos being unmuted (`speaker-wave` on heroicons). Tapping this icon switches _all_ videos to muted
- The muted/unmuted state is global for all videos, but the button to mute/unmute is in the bottom right hand corner of every video.
- If a video scrolls off the page, it should be paused
- Tapping the video anywhere cycles through two states: paused & playing.
- The videos will loop infinitely.

## Tasks

- [x] Remove `controls` attribute, add `autoplay muted loop playsinline` to `<video>` in `post-card.html`
- [x] Add mute/unmute icon button (heroicons `speaker-x-mark` / `speaker-wave`) to bottom-right corner of each video
- [x] Implement global mute/unmute state toggle (tapping icon on any video affects all videos)
- [x] Implement tap-to-play/pause on video element (tap anywhere except the mute button)
- [x] Add IntersectionObserver to autoplay videos when >50% visible and pause when scrolled off
- [x] Handle browsers that block autoplay (leave video paused until user taps)
- [x] Style: hide default controls, position mute button, add any play/pause visual feedback

## Summary of Changes

- Updated `post-card.html`: replaced `<video controls>` with `<video loop playsinline muted>` wrapped in `.video-wrap` div with mute button
- Added `muted.svg` and `unmuted.svg` heroicons to `embed.go` and registered in `site.go`
- Added CSS for `.video-wrap`, `.video-mute-btn` with global mute state toggle via `body.video-unmuted`
- Added JS: global mute toggle, tap-to-play/pause, IntersectionObserver (50% threshold) for autoplay/pause, autoplay-blocked fallback
- Also fixed chaos-f7yj: video-only carousels adapt aspect ratio to video dimensions (clamped 4:5 to 16:9)
