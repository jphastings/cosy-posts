---
# chaos-gvns
title: Rate-limit login emails with exponential backoff
status: todo
type: feature
created_at: 2026-03-07T23:56:58Z
updated_at: 2026-03-07T23:56:58Z
---

Prevent abuse of the magic link login flow by rate-limiting requests to send login emails. If many requests come in within a short window, artificially delay responses with exponential backoff.

## Behaviour

- Track login email requests globally (not per-email, to avoid enumeration)
- If 10+ requests arrive within a 10-minute window, begin adding artificial delay before responding
- Delay should increase exponentially as more requests come in
- The delay applies to the HTTP response time (the request still succeeds or fails as normal, just slower)
- In-memory tracking is fine (resets on server restart)

## Tasks

- [ ] Add a rate tracker for login email requests (sliding window or similar)
- [ ] Implement exponential backoff delay when threshold is exceeded
- [ ] Apply delay in the login/magic-link handler before sending the response
