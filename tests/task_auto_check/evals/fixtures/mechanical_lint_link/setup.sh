#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api"
cat > "$target/proj/docs/api.md" <<'EOF'
# API

## Pagination

Documented pagination behavior appears here.
EOF
# The staged code makes the task's premise true: pagination.py already emits
# next_cursor and omits it on the final page, exactly as the task Context and
# Approach claim, so the premise check clears and the broken link stays the
# only mechanical finding.
cat > "$target/proj/src/api/pagination.py" <<'EOF'
DEFAULT_PAGE_SIZE = 50


def paginate(items, cursor=None):
    """Return one page and the next_cursor token, omitted on the final page."""
    start = int(cursor) if cursor else 0
    page = items[start:start + DEFAULT_PAGE_SIZE]
    next_start = start + DEFAULT_PAGE_SIZE
    if next_start >= len(items):
        return {"items": page}
    return {"items": page, "next_cursor": str(next_start)}
EOF

# Sibling task that makes the broken link's correct target determinable:
# the only on-disk match for the `cursor contract` reference.
cat > "$target/proj/tasks/api_cursor-contract.md" <<'EOF'
---
description: Define the cursor pagination contract shared by API list endpoints.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# API cursor pagination contract

## Goal

Define the opaque cursor token contract used by API list endpoints.

## Context

`src/api/pagination.py` issues page tokens; `docs/api.md` documents pagination.

## Approach

Specify the cursor token encoding and the contract list endpoints honor.

## Acceptance

- `docs/api.md` documents the cursor token format under the pagination section.
EOF

# Target task: readiness-ready, but its Context cross-reference link points at
# `api_cursor.md`, which does not exist. The single determinable on-disk match
# is `api_cursor-contract.md`, so mechanical finalization re-points the link.
cat > "$target/proj/tasks/api_pagination-ready.md" <<'EOF'
---
description: Document the API next_cursor response field so clients can page through list results deterministically.
scope: "api"
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# API cursor pagination response docs

## Goal

Document the `next_cursor` response field on API list endpoints so clients know how to request the following page after a partial result.

## Context

`docs/api.md` documents public API response behavior. `src/api/pagination.py` already emits `next_cursor`. The cursor token format is fixed by the [cursor contract](api_cursor.md).

## Approach

Update the pagination documentation in `docs/api.md` to describe the existing `next_cursor` field returned by API list endpoints, including its absence on the final page.

## Acceptance

- `docs/api.md` documents `next_cursor` under the pagination section, including the final-page case where it is omitted.
- Running `grep -nE 'next_cursor' docs/api.md` after the docs edit extracts the documented cursor field, and running `grep -nE 'DEFAULT_PAGE_SIZE' src/api/pagination.py` extracts the default page size; both describe the same pagination flow.
EOF

commit_proj "$target"
