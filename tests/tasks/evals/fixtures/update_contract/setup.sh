#!/usr/bin/env bash
# update_contract fixture: a git-tracked backlog with TWO open tasks, one
# of which the prompt asks to update. It stages the hub `<update>` workflow
# so the base `task` skill's `<output_contract>` has all four of its parts
# to report on, each with a filesystem observable behind it:
#
#   files touched          -> exactly one of the two tasks may change, so a
#                             report naming tasks/auth_token-rotation.md is
#                             checkable against the git status of the tree
#   status / lifecycle     -> the task stays open in tasks/ (an update is an
#                             edit, never a close-out), so the contract's
#                             "no lifecycle move" branch is the true one
#   linter outcome         -> the seeded backlog lints clean and must still
#                             lint clean after the edit
#   assumptions / calls    -> the body carries TWO `TBD` placeholders the
#                             prompt settles, leaving genuine judgement
#                             calls (where the overlap detail lands, whether
#                             the frontmatter description widens) for the
#                             report to surface
#
# The stale 2020-01-01 stamps make the `updated` bump unambiguous, as in the
# sibling `update` fixture; this fixture differs from that one by grading the
# hub's REPORTING shape rather than the edit mechanics alone.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"

cat > "$proj/tasks/auth_token-rotation.md" <<'EOF'
---
description: rotate issued API tokens on a fixed schedule instead of letting them live forever
scope: "auth"
created: 2020-01-01T00:00:00
updated: 2020-01-01T00:00:00
status: open
reported-by: Test User
---

# Rotate API tokens on a schedule

## Goal

An issued API token rotates on a fixed schedule rather than living forever, so
a leaked token stops working without an operator revoking it by hand.

## Context

Tokens are minted in `src/auth/tokens.py` and carry no expiry today.

## Approach

Stamp each token with an expiry at mint time and rotate it on the schedule. The
length of the rotation window is TBD. Whether a rotated token keeps working for
a grace period after its replacement is issued is TBD as well.

## Acceptance

- A token older than the rotation window stops authenticating.
EOF

cat > "$proj/tasks/auth_session-timeout.md" <<'EOF'
---
description: expire an idle web session after a fixed period of inactivity
scope: "auth"
created: 2020-01-01T00:00:00
updated: 2020-01-01T00:00:00
status: open
reported-by: Test User
---

# Expire idle web sessions

## Goal

An idle browser session expires rather than staying signed in indefinitely.

## Context

Session state lives in `src/auth/session.py`.

## Approach

Track a last-seen time per session and drop a session past the idle limit.

## Acceptance

- A session idle past the limit is rejected on its next request.
EOF

git_commit_all "$proj" "seed: two open auth tasks, one carrying unsettled TBD details"

echo "update_contract sandbox staged at $proj"
