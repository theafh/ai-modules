#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$HERE/../_common.sh"

target="${1:?target dir required}"
init_proj "$target"

mkdir -p "$target/proj/src/auth"

cat > "$target/proj/src/auth/tokens.py" <<'EOF'
"""API token issue, lookup, and the revocation list."""

_STORE: dict[str, str] = {}
_REVOKED: set[str] = set()


def lookup(token):
    """Return the tenant a token belongs to, or None when unknown."""
    if token in _REVOKED:
        return None
    return _STORE.get(token)


def revoked_tokens():
    """Return the revoked tokens."""
    return _REVOKED
EOF

cat > "$target/proj/src/auth/rotation.py" <<'EOF'
"""Hourly token rotation job."""

from src.auth import tokens

ROTATION_INTERVAL_SECONDS = 3600
_HISTORY: list[str] = []


def run_rotation():
    """Re-read the revocation list and retire every token it names."""
    for token in tokens.revoked_tokens():
        _retire(token)


def _retire(token):
    """Drop a revoked token from the issuing records. Writes nothing down."""
    _HISTORY.append(token)
EOF

# The link target. It owns the retention window the target task's Acceptance
# item measures against, which is what makes that item's link load-bearing.
cat > "$target/proj/tasks/api_token-rotation.md" <<'EOF'
---
description: Move the hourly token rotation job onto the shared scheduler and set the retention window for rotation history.
scope: src/auth
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
status: open
reported-by: Harness
---

# Token rotation runs on the shared scheduler

## Goal

Run the hourly token rotation job on the shared scheduler so a worker restart
no longer skips a rotation, and bound how long `_HISTORY` grows.

## Context

`src/auth/rotation.py` runs `run_rotation()` from a per-worker timer with
`ROTATION_INTERVAL_SECONDS = 3600`, appending to `_HISTORY` without ever
pruning it.

## Approach

Register the job with the shared scheduler, drop the per-worker timer, and
set the rotation history retention window to 30 days.

## Acceptance

- `src/auth/rotation.py` registers the rotation job with the shared
  scheduler.
- Rotation history older than the retention window is pruned.
EOF

# Target task. The two sites are `## Goal` and one `## Acceptance` item, and
# `## Context` says nothing about the sibling on purpose. Both copies state the
# same account, that the linked task sets the retention window, and each is
# load-bearing for its own section: Goal states the outcome an operator sees,
# the item states the check that proves it. Neither section can absorb the
# other's copy, and Context offers no escape hatch to trim, so every gathering
# available strips a section of what its own contract owes and the finding is
# surfaced. Stripping only a link leaves both clauses standing and moves no
# material, which the protocol's disposition rule rules out as well.
cat > "$target/proj/tasks/api_retirement-audit-log.md" <<'EOF'
---
description: Record an audit row for every token retirement so an operator can answer which tokens were retired and when.
scope: src/auth
created: 2026-01-01T00:00:00Z
updated: 2026-01-01T00:00:00Z
status: open
reported-by: Harness
---

# Audit log for token retirements

## Goal

Record an audit row for every token retirement, expiring each row on the same
retention window [api_token-rotation](api_token-rotation.md) sets for rotation
history, so an operator never finds a retirement whose audit row has already
gone.

## Context

`src/auth/rotation.py` retires revoked tokens in `_retire()` on each hourly
pass and writes nothing down beyond appending to `_HISTORY`, which nothing
prunes.

## Approach

Write one audit row per retirement from `_retire()`, carrying the token and
the time it was retired, and prune rows past that window.

## Acceptance

- `_retire()` writes exactly one audit row, carrying the token and the
  retirement time, for each token it retires.
- The audit log prunes rows past the same retention window
  [api_token-rotation](api_token-rotation.md) sets for rotation history.
EOF

commit_proj "$target"
