#!/usr/bin/env bash
# finish fixture: a git-tracked backlog with the target open task, a
# sibling open task whose body links to it, AND an already-archived task
# whose body links to it via ../ (legal while the target is open).
# task_finish must set the status, git mv the file to archive/, re-point
# BOTH inbound links — the open sibling to archive/<file>, the archived
# one from ../<file> to the sibling path — and re-lint.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/tasks/api_rate-limit.md" <<EOF
---
description: add request rate limiting to the public API
scope: "api"
created: $now
updated: $now
status: audited
reported-by: Test User
implemented-by: Test User
---

# Add API rate limiting

## Goal

Reject requests over 100/min with a 429.

## Acceptance

- Requests above the threshold receive HTTP 429.
EOF

cat > "$proj/tasks/api_throttle-config.md" <<EOF
---
description: make the throttle window configurable
scope: "api"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Configurable throttle window

## Context

Builds on [API rate limiting](api_rate-limit.md).

## Acceptance

- The window is read from config.
EOF

cat > "$proj/tasks/archive/api_legacy-notes.md" <<EOF
---
description: archived groundwork notes that reference the rate-limit task
scope: "api"
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Legacy throttling groundwork

## Context

Superseded by [the rate-limit work](../api_rate-limit.md).
EOF

git_commit_all "$proj" "seed: rate-limit task plus open and archived tasks that link to it"

echo "finish sandbox staged at $proj"
