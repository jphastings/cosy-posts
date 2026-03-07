---
# chaos-kbkg
title: 'iOS: info button and site info sheet'
status: todo
type: task
created_at: 2026-03-07T23:18:10Z
updated_at: 2026-03-07T23:18:10Z
blocked_by:
    - chaos-20c4
---

Add an info-circle button next to the site name in the iOS app header. Tapping it fetches GET /api/info/site and displays the rendered HTML in a sheet. The API endpoint already exists and returns {"html": "..."} with Accept-Language locale support.
