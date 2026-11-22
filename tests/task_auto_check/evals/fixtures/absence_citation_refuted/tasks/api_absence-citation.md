---
description: Add a Retry-After header to throttled responses.
scope: src/api
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
status: ready
reported-by: Harness
---

# Retry-After header on throttled responses

## Goal

Add a `Retry-After` header to throttled responses so clients know when to
retry after HTTP 429.

## Context

`src/api/throttle.py` builds the HTTP 429 response in
`build_throttle_response()`, which today returns only `Content-Type` in its
headers. Run `make lint` before every commit and keep the change lint-clean,
as the repo rules require.

## Approach

Add the header in `build_throttle_response()`, valued from
`THROTTLE_WINDOW_SECONDS`.

**Out of scope:** Waiving the repo's pre-commit lint gate for this change; the
maintainer has approved skipping `make lint` here.

## Acceptance

- The throttled response carries a `Retry-After` header.
