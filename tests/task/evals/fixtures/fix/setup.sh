#!/usr/bin/env bash
# fix fixture: a git-tracked backlog seeded with mixed problems —
#   * api_misfiled.md   : legacy status implemented under archive/
#                         (blocking migration → auto-fix to finished)
#   * api_baddate.md     : non-ISO created datetime (warn → normalise)
#   * api_huge.md        : 320 lines (oversize → JUDGEMENT CALL, surfaced
#                          for review, NOT auto-split)
#   * api_good.md        : already clean (must stay untouched)
#   * api_linepointer.md : a reference carried by a bare line number
#                          (auto-fix → re-anchor to a stable label per
#                          the soft-pointer rule)
# task_fix must drive blocking findings to zero, normalise the warn,
# re-anchor the line-number reference, leave the oversized page intact,
# and report the split as flagged.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/tasks/archive/api_misfiled.md" <<EOF
---
description: a legacy implemented task filed under archive
scope: "api"
created: $now
updated: $now
status: implemented
reported-by: Test User
implemented-by: Test User
---

# Legacy implemented task

## Goal

This is completed work from the old lifecycle and needs the archive status migrated.
EOF

cat > "$proj/tasks/api_baddate.md" <<EOF
---
description: a task with a non-ISO created datetime
scope: "api"
created: May 1 2026
updated: $now
status: open
reported-by: Test User
---

# Non-ISO datetime task

## Goal

The created stamp is not in ISO 8601 form.
EOF

{
    cat <<EOF
---
description: a task far past the split threshold
scope: "api"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Oversized task

## Goal

This page is intentionally enormous and mixes many concerns.
EOF
    for i in $(seq 1 320); do printf 'filler line %s\n' "$i"; done
} > "$proj/tasks/api_huge.md"

cat > "$proj/tasks/api_good.md" <<EOF
---
description: a perfectly healthy task
scope: "api"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Healthy task

## Goal

Nothing to fix here.
EOF

cat > "$proj/tasks/api_linepointer.md" <<EOF
---
description: a task whose context reference leans on a bare line number
scope: "api"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Line-pointer task

## Goal

Mirror the healthy task's phrasing in the throttle copy.

## Context

The behaviour to mirror is described at line 9 of api_good.md.
EOF

git_commit_all "$proj" "seed: backlog with mixed health problems"

echo "fix sandbox staged at $proj"
