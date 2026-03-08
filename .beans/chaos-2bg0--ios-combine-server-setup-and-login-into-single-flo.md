---
# chaos-2bg0
title: 'iOS: combine server setup and login into single flow with email field'
status: completed
type: task
priority: normal
created_at: 2026-03-07T23:49:43Z
updated_at: 2026-03-08T09:03:08Z
---

The current login flow doesn't work on simulator because the WKWebView can't handle cosy:// deep links. Combine ServerSetupView and LoginView so the app collects both server URL and email, calls POST /auth/send directly, and shows a 'check your email' message.

## Summary of Changes\n\n- Combined ServerSetupView and LoginView into a single screen collecting both server URL and email\n- Added sendMagicLink() to AuthManager that calls POST /auth/send directly\n- Updated auth.go to return JSON when Accept: application/json is set\n- Removed LoginView.swift and WKWebView dependency\n- Simplified RootView routing to authenticated vs not

- Added manual token entry sheet for environments where deep links don't work\n- Fixed syncAuth not being called after manual token login (onChange of sessionToken)\n- Extracted verifyToken() from handleDeepLink for reuse
