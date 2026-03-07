---
# chaos-t3u0
title: Fix 'About this site' popup
status: completed
type: bug
priority: normal
created_at: 2026-03-06T21:35:43Z
updated_at: 2026-03-07T21:02:43Z
---

The 'About this site' sheet that springs from the name of the site in the bottom middle of the app currently only shows the domain name.

It should show the site name, stats (e.g. post count, member count), and a URL linking to the site with the auth token from the app embedded so the user doesn't need to log in again.

The button that opens it should be the name of the app too (as retrieved from the API, rather than just the domain name)

## Tasks\n\n- [x] API: Add member count to /api/info response\n- [x] iOS: Load site info at launch, show site name on bottom button\n- [x] iOS: Add 'Visit Site' link with auth token to the sheet\n- [x] iOS: Show member count in the sheet\n- [x] Site: Support multilingual posts (index.{lang}.md)\n- [x] Site: Show language switcher on posts with translations

## Summary of Changes\n\n### API\n- Added `members` count to `/api/info` response (counts unique entries from can-post.csv + can-view.csv)\n\n### iOS App\n- Bottom toolbar button now shows the site name (fetched from API on launch) instead of just the domain name\n- SiteInfoSheet now shows member count alongside other stats\n- Added "Visit Site" link in the sheet that opens the site in Safari\n- Site info is loaded once at ContentView appear and shared with the sheet\n\n### Website (multilingual)\n- Posts can now have translation files named `index.{lang}.md` (e.g. `index.es.md`)\n- Translations are parsed from frontmatter `locale` field or inferred from filename\n- Post cards show language tabs (e.g. `en` / `es`) when translations exist\n- Clicking a tab switches the displayed body text; media is shared across all languages\n- CSS for language tab pills with active state styling
