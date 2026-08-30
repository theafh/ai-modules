#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# The cited artifacts exist with the exact spans the task's claims rest on, so
# a first-call gate can clear every checklist item on a genuine comparative
# reading and its citations survive a refute-by-default pass: the throttle
# module builds the 429 response without a Retry-After header, and the docs
# carry a response-header section that does not list it yet.
cat > "$target/proj/src/api/throttle.py" <<'EOF'
"""Request throttling. Emits HTTP 429 when a client exceeds its budget."""

THROTTLE_WINDOW_SECONDS = 60


def build_throttle_response():
    """Return the HTTP 429 response sent to a throttled client."""
    return {
        "status": 429,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error": "too many requests"}',
    }
EOF

# The existing test asserts only the status code and body, never the exact
# headers dict, so adding Retry-After stays additive and collides with nothing.
cat > "$target/proj/tests/test_throttle.py" <<'EOF'
from src.api.throttle import build_throttle_response


def test_throttled_response_is_429():
    response = build_throttle_response()
    assert response["status"] == 429


def test_throttled_response_body_names_the_error():
    response = build_throttle_response()
    assert "too many requests" in response["body"]
EOF

cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Response headers

- `Content-Type` — the media type of the response body.
- `X-Request-Id` — echo of the request identifier when the client sent one.

## Throttling

Clients exceeding their request budget receive HTTP 429 with a JSON error
body built by `build_throttle_response()`.
EOF

cat > "$target/proj/tasks/api_retry-header.md" <<'EOF'
---
description: Add a Retry-After header to API throttling responses so clients know when to retry after HTTP 429.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Retry-After header on throttling responses

## Goal

Add a `Retry-After` response header to API throttling responses so clients
know when to retry after HTTP 429.

## Context

`src/api/throttle.py` builds the HTTP 429 response in
`build_throttle_response()`, which today returns only `Content-Type` in its
headers. The module's `THROTTLE_WINDOW_SECONDS = 60` names the throttle
window. `docs/api.md` documents public response headers under its
`## Response headers` section, which does not yet list `Retry-After`.
`tests/test_throttle.py` covers the current 429 response with pytest.

## Approach

Update `build_throttle_response()` to include `Retry-After` in its headers,
valued as `THROTTLE_WINDOW_SECONDS` in seconds, then document the header in
the `## Response headers` section of `docs/api.md`.

## Acceptance

- A pytest test added to the existing `tests/test_throttle.py` confirms the
  throttled response carries HTTP 429 and a `Retry-After` header value equal
  to `THROTTLE_WINDOW_SECONDS`.
- `docs/api.md` lists `Retry-After` under its `## Response headers` section.
EOF

commit_proj "$target"
