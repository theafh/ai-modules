#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

# Supply the current-state evidence the unchanged ready task names. The
# requested Retry-After behavior remains absent so readiness is still valid.
mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Response headers

Throttled HTTP 429 responses include `Content-Type: application/json`.
EOF

cat > "$target/proj/src/api/throttle.py" <<'EOF'
THROTTLE_WINDOW_SECONDS = 60


def build_throttle_response():
    """Return the HTTP 429 response for a throttled request."""
    return {
        "status": 429,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error": "too many requests"}',
    }
EOF

cat > "$target/proj/tests/test_throttle.py" <<'EOF'
from src.api.throttle import build_throttle_response


def test_throttled_response_is_429():
    response = build_throttle_response()
    assert response["status"] == 429
EOF

cat > "$target/proj/tasks/api_ready-task.md" <<'EOF'
---
description: Ready task fixture with concrete goal, context, approach, and acceptance.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# Ready API retry fixture

## Goal

Add a `Retry-After` response header to API throttling responses so clients know when to retry after HTTP 429.

## Context

`docs/api.md` documents public API response headers. `src/api/throttle.py` emits the HTTP 429 response.

## Approach

Update the throttle response builder to include `Retry-After` in seconds using the throttle window duration from `src/api/throttle.py`, then document the header in `docs/api.md`.

## Acceptance

- A unit test confirms throttled requests receive HTTP 429 with a `Retry-After` header value equal to the throttle window duration in seconds.
- `docs/api.md` documents the header under the response-header section.
EOF

commit_proj "$target"
