---
# chaos-nor2
title: Serve site favicon.svg from content dir
status: in-progress
type: feature
created_at: 2026-05-01T14:42:04Z
updated_at: 2026-05-01T14:42:04Z
---

When the content directory contains a favicon.svg file, serve it as the favicon and use it as the site's logo wherever appropriate.

## Todos
- [ ] Add public GET /favicon.svg route that serves from content_dir/favicon.svg (404 if missing)
- [ ] Whitelist /favicon.svg in auth middleware so it loads on the login page
- [ ] Add <link rel="icon" type="image/svg+xml" href="/favicon.svg"> to base.html (conditional on existence)
- [ ] Show logo next to site name in site-header on home/single pages (conditional)
- [ ] Add favicon link + logo above heading on login + 'check your email' pages
- [ ] CSS for .site-logo and .login-logo
- [ ] Build and verify in browser at chaos.awaits.us.test
