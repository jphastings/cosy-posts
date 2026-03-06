---
# chaos-3g6v
title: Contact preference dialog
status: completed
type: feature
priority: normal
created_at: 2026-03-05T13:04:15Z
updated_at: 2026-03-06T16:14:51Z
---

Replace select dropdown with icon button + dialog for contact method preferences. Drag-to-reorder rows, checkboxes, immediate localStorage persistence.

## Summary of Changes\n\nReplaced the broken `<select>` dropdown for contact method preferences with:\n- Icon button in navbar showing the current top-preference method icon\n- Native `<dialog>` with drag-to-reorder rows, checkboxes, and immediate localStorage persistence\n- Email always checked and disabled\n- Close via × button, Esc, or backdrop click

## Summary of Changes

- Replaced select dropdown with icon button + dialog for contact preferences
- Drag-to-reorder using pointer events (touch + mouse support)
- 'Not shown' divider: items below are disabled/desaturated, divider hidden when all items shown
- Contact buttons hidden when no enabled method matches the author
- Bookmark filter label hidden when empty via :empty pseudo-class
- CSS reset excludes dialog for native centering support
