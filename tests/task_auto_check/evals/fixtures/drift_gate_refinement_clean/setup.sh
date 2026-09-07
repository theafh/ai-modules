#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_timeout-headers.md" <<'EOF'
---
description: Document API timeout headers.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
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
created: 2026-01-01T00:00:00
updated: 2026-01-02T00:00:00
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
