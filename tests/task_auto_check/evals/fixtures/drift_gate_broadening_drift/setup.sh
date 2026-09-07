#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_search-pagination.md" <<'EOF'
---
description: Add cursor pagination to public API search results.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API search cursor pagination

## Goal

Add cursor pagination to the public API search endpoint so clients can retrieve result sets beyond the first page.

## Context

`src/api/search.py` returns the first page of results. `docs/api.md` documents search parameters.

## Approach

Add cursor input/output handling to the search endpoint and document the cursor contract.

## Acceptance

- A unit test confirms search responses include a next cursor when more results exist.
- `docs/api.md` documents the cursor request and response fields.
EOF

commit_proj "$target"

cat > "$target/proj/tasks/api_search-pagination.md" <<'EOF'
---
description: Add cursor pagination to public API search results.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-02T00:00:00
status: open
reported-by: Harness
---

# API search cursor pagination

## Goal

Add cursor pagination to the public API search endpoint and ship a webhook delivery surface that notifies clients when new search-index rows arrive.

## Context

`src/api/search.py` returns the first page of results. `docs/api.md` documents search parameters. `src/api/webhooks.py` does not yet exist.

## Approach

Add cursor input/output handling to the search endpoint, document the cursor contract, and add a webhook delivery route for search-index updates.

## Acceptance

- A unit test confirms search responses include a next cursor when more results exist.
- `docs/api.md` documents the cursor request and response fields.
- A unit test confirms webhook delivery fires when new search-index rows arrive.
EOF
