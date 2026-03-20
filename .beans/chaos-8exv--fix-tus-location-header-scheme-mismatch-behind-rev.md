---
# chaos-8exv
title: Fix TUS Location header scheme mismatch behind reverse proxy
status: completed
type: bug
priority: normal
created_at: 2026-03-20T06:53:00Z
updated_at: 2026-03-20T07:01:26Z
---

Server behind HTTPS reverse proxy returns Location with http:// scheme. TUS client uses this absolute URL for PATCH, which fails. Fix client to resolve Location relative to its endpoint.


## Summary of Changes

**api/upload/handler.go:** Added relativeLocationWriter middleware that rewrites tusd's absolute Location headers to relative paths (e.g. `/files/{id}`). This prevents scheme/host mismatches when behind a reverse proxy.

**TUSClient.swift:** When the server returns an absolute URL in the Location header (e.g. `http://example.com/files/abc`), the client now extracts just the path and resolves it against the configured endpoint URL. This preserves the correct scheme (https) and host when behind a reverse proxy.

**UploadFlowTests.swift:** Added `absoluteHTTPLocation` flag to TUSMockProtocol and `testAbsoluteHTTPLocationResolvedToHTTPS` test verifying that PATCH requests use the endpoint's HTTPS scheme even when Location returns HTTP.
