#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
: > "$target/proj/docs/api.md"
: > "$target/proj/src/api/health.py"

cat > "$target/proj/tasks/api_healthcheck.md" <<'EOF'
---
description: Add a /healthz liveness endpoint to the public API.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API /healthz liveness endpoint

## Goal

Add a `/healthz` liveness endpoint to the public API so load balancers can probe service health without authentication.

## Context

`src/api/health.py` is the designated module for health handlers and is currently empty. `docs/api.md` documents public API endpoints.

## Approach

Implement a `/healthz` GET handler in `src/api/health.py` that returns HTTP 200 with body `ok` and requires no authentication, then document the endpoint in `docs/api.md`.

## Acceptance

- A unit test confirms `GET /healthz` returns HTTP 200 with body `ok` and requires no authentication.
- `docs/api.md` documents the `/healthz` endpoint.
EOF

commit_proj "$target"
