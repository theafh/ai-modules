#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/docs" "$target/proj/src/api" "$target/proj/tests"

# --- Interacting code the task never links, reachable via the `page_size`
#     touch-point. A repo search for the task's config touch-point lands here;
#     reading pagination.py alone never reveals it.
cat > "$target/proj/src/api/limits.py" <<'EOF'
"""Response-size guard applied by the API middleware to every list response.

Shipped after the pagination task below was filed, and independent of
pagination.py: the middleware re-checks the realized page against a hard cap
regardless of how the default page_size was chosen.
"""

# Hard cap on items returned per page. A load invariant, not a tunable — never
# raised without a capacity review.
MAX_PAGE_SIZE = 100


def enforce_page_size(page_size):
    """Clamp the effective page_size down to MAX_PAGE_SIZE.

    Applied to every list endpoint's response, so a configured default
    page_size above the cap is silently reduced to MAX_PAGE_SIZE before the
    response is sent — the caller gets 100 items with no error.
    """
    return min(page_size, MAX_PAGE_SIZE)
EOF

# --- The edit site the task links. Premise reads this and finds exactly what
#     the task describes (paginate() defaults page_size to 50); it does not
#     reveal limits.py.
cat > "$target/proj/src/api/pagination.py" <<'EOF'
"""Public API pagination."""


def paginate(items, page_size=50):
    """Return one page of items."""
    return items[:page_size]
EOF

# --- Decoy: shares no touch-point with the task. The scan must not need to
#     read this to reach its finding.
cat > "$target/proj/src/api/auth.py" <<'EOF'
"""Bearer-token authentication middleware. Unrelated to pagination."""


def authenticate(token):
    """Return True when the bearer token is valid."""
    return token == "valid"
EOF

# Existing test anchors the pytest convention and the tests/ location. It
# exercises explicit page_size, not the default the task changes, so the task
# leaves it valid.
cat > "$target/proj/tests/test_pagination.py" <<'EOF'
from src.api.pagination import paginate


def test_paginate_limits_to_explicit_page_size():
    assert paginate([1, 2, 3, 4, 5], page_size=2) == [1, 2]
EOF

# Docs describe pagination generically without stating the default value, so
# the task's change leaves no documented number stale.
cat > "$target/proj/docs/api.md" <<'EOF'
# API reference

## Pagination

List endpoints return one page of results at a time.
EOF

cat > "$target/proj/tasks/api_page-size-config.md" <<'EOF'
---
description: Read the default API page size from the PAGE_SIZE environment variable, replacing paginate()'s hardcoded default of 50 in src/api/pagination.py.
scope: src/api
created: 2026-01-01T00:00:00
updated: 2026-01-01T00:00:00
status: open
reported-by: Harness
---

# Configurable default page size for the API

## Goal

Let operators set the default number of items per page through the `PAGE_SIZE`
environment variable, replacing the hardcoded default of 50 in
`src/api/pagination.py`. Today `paginate()` hardcodes `page_size=50`; after this
change the default comes from the environment, so a deployment can tune it
without a code change.

## Context

`src/api/pagination.py`'s `paginate()` hardcodes its `page_size` default to 50,
with no configuration path. `tests/test_pagination.py` covers explicit
page-size slicing with `pytest`.

## Approach

Change `paginate()` in `src/api/pagination.py` so its `page_size` parameter
defaults to `None`, and when it is `None` read the default at call time via
`int(os.environ.get("PAGE_SIZE", "50"))` inside the function body, replacing the
hardcoded `50` default. Reading at call time rather than import time lets a
deployment set `PAGE_SIZE` without a code change, and keeps the default at 50
when `PAGE_SIZE` is unset.

**Out of scope:** wiring `PAGE_SIZE` into non-pagination call sites — this task
changes only the pagination default.

## Acceptance

- `paginate()` in `src/api/pagination.py` defaults `page_size` to `None` and,
  when it is `None`, reads `int(os.environ.get("PAGE_SIZE", "50"))` at call time
  instead of the hardcoded `50` default.
- With `PAGE_SIZE` unset, `paginate([...])` still defaults to 50 items, matching
  today's behavior.
- A test in `tests/test_pagination.py` (pytest, following the existing case)
  uses `monkeypatch.setenv("PAGE_SIZE", "500")` and asserts
  `paginate(list(range(1000)))` returns pages of 500 items.
EOF

commit_proj "$target"
