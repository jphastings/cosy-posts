---
# chaos-gyh4
title: Turn site name in bottom bar into icon button
status: completed
type: feature
priority: normal
created_at: 2026-03-08T09:23:57Z
updated_at: 2026-03-10T06:40:29Z
---

The site name text in the bottom bar of the iOS app should become a button with an icon, styled like the other bottom bar buttons.

## Behaviour

- The site name appears as a labelled icon button, matching the style of the other bottom bar buttons
- It should be visually centred in the bar when there is enough space
- When space is constrained, it collapses to just an icon (no label), aligned with the other icons
- Tapping it should navigate to the site / home view (or whatever the site name currently does)

## Tasks

- [x] Remove the locale name from the right of the locale button (currently it has EN or ES there, we can just have the icon, it'll make more space)
- [x] Replace site name text with a labelled icon button
- [x] Match the style of existing bottom bar buttons
- [x] Centre the button when space allows
- [x] Collapse to icon-only when space is tight

## Summary of Changes

In ContentView.swift:
- Removed locale code text from globe button (now icon-only)
- Replaced ZStack layout with single HStack; site name is now a labelled icon button (house icon) with Spacers on both sides for centering
- Uses standard SwiftUI Label which automatically collapses to icon-only when space is constrained
- Styled with .secondary foreground to match other toolbar items
