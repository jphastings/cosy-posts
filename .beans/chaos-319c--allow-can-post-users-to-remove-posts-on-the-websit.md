---
# chaos-319c
title: Allow can-post users to remove posts on the website
status: todo
type: feature
priority: normal
created_at: 2026-03-06T21:33:15Z
updated_at: 2026-03-06T21:39:14Z
---

Add a delete/remove post action on the website for users with can-post permissions. Consider adding a new icon next to the bookmark icon (using heroicons.com).

## Notes\n\n- Permanent deletion: remove post directory from content_dir on disk\n- This is on the website (not the iOS app)\n- Needs an API endpoint for deletion\n- Trigger site rebuild after removal
