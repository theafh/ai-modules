#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# Real, varied surrounding code so "no false alarm" is meaningful: the scan has
# a populated repo to search — pagination, an auth check, and limits.py's
# MAX_PAGE_SIZE cap — yet the request-id task below shares no touch-point with
# any of it.
cat > "$target/proj/src/api/pagination.py" <<'EOF'
"""Public API pagination."""

DEFAULT_PAGE_SIZE = 50


def paginate(items, page_size=DEFAULT_PAGE_SIZE):
    """Return one page of items."""
    return items[:page_size]
EOF

cat > "$target/proj/src/api/limits.py" <<'EOF'
"""Response-size guard. MAX_PAGE_SIZE caps items returned per page."""

MAX_PAGE_SIZE = 100


def enforce_page_size(page_size):
    """Clamp the effective page_size down to MAX_PAGE_SIZE."""
    return min(page_size, MAX_PAGE_SIZE)
EOF

cat > "$target/proj/src/api/auth.py" <<'EOF'
"""Bearer-token authentication middleware."""


def authenticate(token):
    """Return True when the bearer token is valid."""
    return token == "valid"
EOF

# Existing test establishes the pytest convention and the tests/ location, so a
# task adding a test has a concrete pattern to follow.
cat > "$target/proj/tests/test_auth.py" <<'EOF'
from src.api.auth import authenticate


def test_authenticate_accepts_valid_token():
    assert authenticate("valid") is True


def test_authenticate_rejects_invalid_token():
    assert authenticate("nope") is False
EOF

# Docs describe only pagination and auth — nothing about request IDs or tracing,
# so the task's change leaves no documented surface stale.
cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Pagination

List endpoints return one page of results at a time; `paginate()` slices the
result set to the page size.

## Authentication

Requests carry a bearer token, validated by `authenticate()`.
EOF

cat > "$target/proj/tasks/api_request-id.md" <<'EOF'
---
description: Add a new_request_id() helper returning a fresh UUID4 string so each API request can carry a unique trace identifier.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: ready
reported-by: Harness
---

# Request-ID generator for the API

## Goal

Add a `new_request_id()` helper that returns a fresh UUID4 string, so each API
request can be tagged with a unique identifier for tracing. The codebase has no
request-ID or tracing facility today; this adds the generator as a
self-contained building block.

## Context

No request-ID, correlation-ID, or tracing facility exists in the codebase. The
existing modules are unrelated: `src/api/pagination.py` slices result pages,
`src/api/limits.py` caps page size, and `src/api/auth.py` validates bearer
tokens. The new helper depends only on the standard-library `uuid` module.

## Approach

Add `src/api/request_id.py` containing `import uuid` and
`def new_request_id() -> str: return str(uuid.uuid4())`. The helper is a pure
generator with no arguments and no shared state, independent of pagination,
limits, and auth.

**Out of scope:** wiring the helper into any request handler or middleware —
this task ships only the generator, and a follow-up adds the call sites.
`docs/api.md` is not updated, because `new_request_id()` is an internal helper
rather than a public API surface it documents.

## Acceptance

- `src/api/request_id.py` defines `new_request_id()` returning
  `str(uuid.uuid4())`.
- Calling `new_request_id()` returns a 36-character string, and two successive
  calls return different values.
- `tests/test_request_id.py`, written with `pytest` following the existing
  `tests/test_auth.py`, asserts both properties: the 36-character length and
  that two calls differ.
EOF

commit_proj "$target"
