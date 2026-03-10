---
# chaos-z9e1
title: Fix share sheet extension on macOS (and possibly iOS)
status: todo
type: bug
created_at: 2026-03-10T12:02:41Z
updated_at: 2026-03-10T12:02:41Z
---

The share sheet extension doesn't seem to work on macOS, and may also be broken on iOS. Needs investigation and fixing.

## Considerations

- Ideally the share sheet should use the full app window rather than a small popover, if that's possible and suitable for the UX
- May need to check the extension's principal class, activation rules, and entitlements
- Test on both macOS and iOS

## Tasks

- [ ] Investigate why the share sheet doesn't appear/work on macOS
- [ ] Test share sheet on iOS and fix if also broken
- [ ] Explore using the full app window for the share sheet if possible
- [ ] Verify activation rules work for images and videos
