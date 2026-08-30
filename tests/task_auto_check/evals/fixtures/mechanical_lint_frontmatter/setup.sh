#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
# The timeouts section is empty on purpose: a placeholder sentence would be a
# stale passage the docs edit must supersede, which draws an
# Edit-items-supersede acceptance finding and a body repair — this eval needs
# the body to gate clean apart from the malformed created value.
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Timeouts
EOF
cat > "$target/proj/src/api/timeout.py" <<'EOF'
REQUEST_TIMEOUT_SECONDS = 30


def timeout_response():
    """Emit the HTTP 504 payload when the request timeout elapses."""
    return 504, {"error": "request timeout", "timeout_seconds": REQUEST_TIMEOUT_SECONDS}
EOF

# Target task: readiness-ready, but `created` is a non-ISO `YYYY/MM/DD` value.
# The unambiguous normalisation is `2026-01-01`; `updated` is bumped to now by
# the mechanical edit that changes the file.
cat > "$target/proj/tasks/api_timeout-ready.md" <<'EOF'
---
description: Document the API request-timeout response so clients know the enforced timeout window behind HTTP 504.
scope: "api"
created: 2026/01/01
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API request-timeout response docs

## Goal

Document the HTTP 504 timeout response on API requests so clients know the enforced timeout window.

## Context

`docs/api.md` documents public API response behavior. `src/api/timeout.py` enforces the request timeout and emits HTTP 504 when it elapses.

## Approach

Update the timeout documentation in `docs/api.md` to describe the existing HTTP 504 behavior and the timeout window enforced by `src/api/timeout.py`.

## Acceptance

- `docs/api.md` documents the HTTP 504 timeout response under the timeouts section.
- Running `grep -nE '504|timeout' docs/api.md` after the docs edit extracts the documented timeout response, and running `grep -nE 'REQUEST_TIMEOUT_SECONDS' src/api/timeout.py` extracts the enforced window; both describe the same timeout flow.
EOF

commit_proj "$target"
