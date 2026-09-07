#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

cat > "$target/proj/tasks/api_search-results.md" <<'EOF'
---
description: Add cursor pagination and CSV export for public API search results.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API search pagination and CSV export

## Goal

Add cursor pagination to the public API search endpoint and ship a CSV export of the same result set so clients can page and download results.

## Context

`src/api/search.py` returns the first page of results. `docs/api.md` documents search parameters.

## Approach

Add cursor input/output handling to the search endpoint, document the cursor contract, and add a CSV export route beside the search handlers.

## Acceptance

- A unit test confirms search responses include a next cursor when more results exist.
- `docs/api.md` documents the cursor request and response fields.
- A unit test confirms the CSV export returns the same result rows as the paged search.
EOF

commit_proj "$target"

cat > "$target/proj/tasks/api_search-results.md" <<'EOF'
---
description: Add cursor pagination to public API search results.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-02T00:00:00
status: ready
reported-by: Harness
---

# API search cursor pagination

## Goal

Add cursor pagination to the public API search endpoint so clients can retrieve result sets beyond the first page.

## Context

`src/api/search.py` returns the first page of results. `docs/api.md` documents search parameters.

## Approach

Add cursor input/output handling to the search endpoint and document the cursor contract.

**Out of scope:** CSV export of search results; a sibling owns that deliverable.

## Acceptance

- A unit test confirms search responses include a next cursor when more results exist.
- `docs/api.md` documents the cursor request and response fields.
EOF
