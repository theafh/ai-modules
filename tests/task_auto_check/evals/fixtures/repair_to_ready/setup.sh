#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# The staged repo supplies the evidence base the repairs draw on: the throttle
# code genuinely lacks Retry-After (the task's gap), the throttle window
# constant settles the header's value, the docs carry the section the repair
# targets, and an existing pytest module anchors any test-shaped acceptance.
# Without this evidence the reviewers face an open product decision no code
# can settle, and the loop correctly stops for a human instead of reaching
# ready.
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Response headers

Documented headers appear here.
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

cat > "$target/proj/tasks/api_retry-after.md" <<'EOF'
---
description: Add Retry-After handling to throttled API responses.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Retry-After for API throttling

## Goal

Add `Retry-After` handling to API throttling responses.

## Context

The implementation lives in the API throttling code.

## Approach

TBD.

## Acceptance

- The retry behavior works properly.
EOF

commit_proj "$target"
