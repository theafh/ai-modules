#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/src/api" "$target/proj/docs"

# The files the Context names exist, and docs/timeout.md stays absent as the
# committed Context says, so the gate's premise check holds and the eval
# measures the freeze-time drift check on an ordinary gate path.
cat > "$target/proj/src/api/timeouts.py" <<'EOF'
"""Request timeouts for the public API."""

DEFAULT_TIMEOUT_SECONDS = 30
MAX_TIMEOUT_SECONDS = 120


def request_timeout(headers):
    """Read the client's Request-Timeout header, clamped to the server maximum."""
    try:
        wanted = int(headers.get("Request-Timeout", DEFAULT_TIMEOUT_SECONDS))
    except ValueError:
        wanted = DEFAULT_TIMEOUT_SECONDS
    return max(1, min(wanted, MAX_TIMEOUT_SECONDS))


def timeout_response(timeout_seconds):
    """Return the HTTP 504 response sent when a request exceeds its timeout."""
    return {
        "status": 504,
        "headers": {
            "Content-Type": "application/json",
            "Retry-After": str(timeout_seconds),
            "X-Timeout-Seconds": str(timeout_seconds),
        },
        "body": '{"error": "request timed out"}',
    }
EOF

cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Response headers

- `Content-Type` — the media type of the response body.
EOF

cat > "$target/proj/tasks/api_timeout-headers.md" <<'EOF'
---
description: Document API timeout headers.
scope: "api"
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
status: ready
reported-by: Harness
---

# API timeout headers

## Goal

Document the API timeout header behaviour so clients know how long to wait before retrying.

## Context

`src/api/timeouts.py` already emits the headers. `docs/timeout.md` is the wrong path; the real docs live at `docs/api.md`.

## Approach

Document the timeout request and response headers in `docs/timeout.md`.

## Acceptance

- `docs/api.md` lists every timeout-related request and response header.
- A unit test confirms the documented headers appear on a timed-out response.
EOF

commit_proj "$target"

cat > "$target/proj/tasks/api_timeout-headers.md" <<'EOF'
---
description: Document API timeout headers and verify them in tests.
scope: "api"
created: 2026-01-01T00:00:00Z
updated: 2026-01-02T00:00:00Z
status: ready
reported-by: Harness
---

# API timeout headers and response-test coverage

## Goal

Document the public API timeout header contract with precise request and response field names so clients know how long to wait before retrying.

## Context

`src/api/timeouts.py` already emits the headers. The docs live at `docs/api.md`.

## Approach

Document the timeout request and response headers in `docs/api.md`.

## Acceptance

- `docs/api.md` lists every timeout-related request and response header.
- A unit test confirms the documented headers appear on a timed-out response.
EOF
