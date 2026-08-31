#!/usr/bin/env bash
# update fixture: a git-tracked backlog with one open task carrying a
# fixed OLD timestamp (2020-01-01) for both created and updated. The base
# `task` skill's <update> workflow must edit the task and bump `updated`
# to the current time from `date`, leaving `created` untouched. The old
# stamp makes the bump unambiguous: after the run `updated` is recent and
# `created` is still 2020-01-01. The task stays open and in the tasks root.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"

cat > "$proj/tasks/api_rate-limit.md" <<'EOF'
---
description: add request rate limiting to the public API
scope: "api"
created: 2020-01-01T00:00:00
updated: 2020-01-01T00:00:00
status: open
reported-by: Test User
---

# Add API rate limiting

## Goal

Reject requests over 100/min with a 429.

## Acceptance

- Requests above the threshold receive HTTP 429.
EOF

git_commit_all "$proj" "seed: an open task with a stale updated timestamp"

echo "update sandbox staged at $proj"
