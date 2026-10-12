#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"
mkdir -p "$target/proj/src/api" "$target/proj/tests"

cat > "$target/proj/src/api/throttle.py" <<'EOF'
THROTTLE_WINDOW_SECONDS = 60


def build_throttle_response():
    return {
        "status": 429,
        "headers": {"Content-Type": "application/json"},
        "body": '{"error": "too many requests"}',
    }
EOF

cat > "$target/proj/tests/test_throttle.py" <<'EOF'
from src.api.throttle import build_throttle_response


def test_throttled_response_is_429():
    assert build_throttle_response()["status"] == 429
EOF

cat > "$target/proj/tasks/api_last-call.md" <<'EOF'
---
description: Add Retry-After to throttled responses while preserving the response body.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Retry-After header with preserved response fields

## Goal

Add Retry-After to throttled responses while preserving the response body.

## Context

`src/api/throttle.py` defines `build_throttle_response()`, which returns HTTP
429, a `Content-Type` header, and a JSON error body. It has no `Retry-After`
header. Its `THROTTLE_WINDOW_SECONDS = 60` constant supplies the retry window.
`tests/test_throttle.py` has `test_throttled_response_is_429`, which proves
only the status code. The module has no other callers or consumers.

## Approach

Update `build_throttle_response()` in `src/api/throttle.py` with these rules:

- Set `Retry-After` to the string form of `THROTTLE_WINDOW_SECONDS`.
- Body preservation rule: Preserve the existing response body unchanged.

## Acceptance

- A test in `tests/test_throttle.py` asserts HTTP 429 and `Retry-After == str(THROTTLE_WINDOW_SECONDS)`.
EOF

commit_proj "$target"
