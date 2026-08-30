#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

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
