#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
: > "$target/proj/docs/api.md"
: > "$target/proj/src/api/metrics.py"

cat > "$target/proj/tasks/api_metrics.md" <<'EOF'
---
description: Expose a /metrics request-count endpoint on the public API.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API /metrics request-count endpoint

## Goal

Expose a `/metrics` endpoint that reports the total request count per public API route so operators can monitor traffic.

## Context

`src/api/metrics.py` is the designated module for the metrics handler and is currently empty. `docs/api.md` documents public API endpoints.

## Approach

Implement a `/metrics` GET handler in `src/api/metrics.py` that returns per-route request totals as JSON, then document the endpoint and its response fields in `docs/api.md`.

## Acceptance

- A unit test confirms `GET /metrics` returns HTTP 200 with a JSON map of route to request count.
- `docs/api.md` documents the `/metrics` endpoint and its response fields.
EOF

commit_proj "$target"
