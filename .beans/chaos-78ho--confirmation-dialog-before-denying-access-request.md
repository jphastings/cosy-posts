---
# chaos-78ho
title: Confirmation dialog before denying access request
status: completed
type: task
priority: high
created_at: 2026-03-30T10:21:18Z
updated_at: 2026-03-30T10:22:26Z
---

Add a confirmation alert before denying an access request, so admins don't accidentally reject someone.

## Summary of Changes\n\nAdded a confirmationDialog on the deny button. Tapping ❌ now shows "Deny access for {email}?" with a destructive "Deny" button and a cancel option. The deny action only fires after confirmation.
