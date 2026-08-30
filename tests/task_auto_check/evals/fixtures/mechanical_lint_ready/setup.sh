#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
# The response-header section is empty on purpose: a placeholder sentence
# would be a stale passage the docs edit must supersede, which draws an
# Edit-items-supersede acceptance finding and a body repair — this eval needs
# the body to gate clean apart from the overlong description.
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Response headers
EOF
# The staged code makes the task's premise true: throttle.py already emits
# HTTP 429 with Retry-After, exactly as the task Context claims, so the
# premise check clears and the only finding left is the overlong description.
cat > "$target/proj/src/api/throttle.py" <<'EOF'
THROTTLE_WINDOW_SECONDS = 60


def build_throttle_response():
    """Return the HTTP 429 response for a throttled request."""
    return {
        "status": 429,
        "headers": {
            "Content-Type": "application/json",
            "Retry-After": str(THROTTLE_WINDOW_SECONDS),
        },
        "body": '{"error": "too many requests"}',
    }
EOF

cat > "$target/proj/tasks/api_lint-ready.md" <<'EOF'
---
description: Add API Retry-After throttling response documentation with an overly elaborated explanatory sentence that should disappear because this frontmatter description repeats body details, implementation hints, and acceptance context far beyond the task linter budget while still naming the API Retry-After throttling scope.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API Retry-After throttling response docs

## Goal

Document the `Retry-After` header on API throttling responses so clients know when to retry after HTTP 429.

## Context

`docs/api.md` documents public API response headers. `src/api/throttle.py` already emits HTTP 429 with `Retry-After`.

## Approach

Update the response-header documentation in `docs/api.md` to describe the existing `Retry-After` behavior for throttled API requests.

## Acceptance

- `docs/api.md` documents `Retry-After` under the response-header section.
- Running `grep -E 'Retry-After|retry.?after|retry_after' docs/api.md` after the docs edit extracts the documented retry delay value, and running `grep -E 'THROTTLE_WINDOW_SECONDS|Retry-After|window|delay' src/api/throttle.py` extracts the throttle window value; both values match.
EOF

commit_proj "$target"
