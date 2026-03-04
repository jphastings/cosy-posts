---
# chaos-gehp
title: 'App: constrain images to screen width'
status: completed
type: bug
priority: normal
created_at: 2026-03-04T23:08:55Z
updated_at: 2026-03-04T23:09:19Z
---

Images in the app carousel can be wider than the screen. They should be limited to screen width with empty space above/below for wide/landscape images.

## Summary of Changes\n\nConstrained multi-item carousel images to screen width using `maxWidth: size.width` alongside the existing height constraint. Landscape images now fit within screen width with empty space above/below.
