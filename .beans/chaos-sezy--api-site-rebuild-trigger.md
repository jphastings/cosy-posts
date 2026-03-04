---
# chaos-sezy
title: 'API: Site rebuild trigger'
status: completed
type: task
priority: normal
created_at: 2026-03-04T20:20:33Z
updated_at: 2026-03-04T20:50:31Z
parent: chaos-y7fz
blocked_by:
    - chaos-3krd
---

When post assembly completes, exec configurable rebuild command as subprocess. Pipe stdout/stderr to configured log file. Non-blocking (don't wait for completion before responding).
