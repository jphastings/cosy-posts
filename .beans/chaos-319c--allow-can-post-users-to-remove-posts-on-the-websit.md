---
# chaos-319c
title: Allow can-post users to remove posts on the website
status: completed
type: feature
priority: normal
created_at: 2026-03-06T21:33:15Z
updated_at: 2026-03-07T22:39:42Z
---

Add a delete/remove post action on the website for users with can-post permissions. Consider adding a new icon next to the bookmark icon (using heroicons.com).

## Notes\n\n- Permanent deletion: remove post directory from content_dir on disk\n- This is on the website (not the iOS app)\n- Needs an API endpoint for deletion\n- Trigger site rebuild after removal

## Summary of Changes

Added post deletion for can-post users:

**API endpoint**: `DELETE /api/posts/{id}` — requires post role, removes the post directory from disk, triggers site rebuild. Returns 403 for non-post users.

**Built-in site**: Delete button (trash icon from heroicons) appears to the left of the bookmark icon, only visible to post-role users. Uses `data-can-delete` attribute on body element driven by the auth role. JS shows a confirmation dialog with the post date before calling the API. On success, the post card is removed from the DOM.

**Files changed**:
- `api/post/delete.go`: New delete handler + findPostDir helper
- `api/site/site.go`: Added roleFunc, SetRoleFunc, trash.svg route, CanDelete in template data
- `api/site/embed.go`: Embedded trash.svg
- `api/site/static/img/trash.svg`: Heroicons trash icon
- `api/site/static/css/style.css`: Delete button styles (hidden by default)
- `api/site/templates/base.html`: data-can-delete attribute + delete JS
- `api/site/templates/post-card.html`: Delete button markup
- `api/main.go`: Wired up DELETE endpoint + SetRoleFunc
