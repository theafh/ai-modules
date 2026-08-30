#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_rate-limit.md" <<'EOF'
---
description: Clarify a per-user API rate-limit task without broadening it.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Per-user API rate limit

## Goal

Throttle each authenticated user to 100 public API requests per minute.

## Context

The current task needs clearer acceptance checks. This is not a global abuse-prevention redesign.

## Approach

Add a per-user fixed-window rate-limit check to the API request path.

## Acceptance

- The API is protected from abusive clients.
EOF

commit_proj "$target"
