#!/usr/bin/env bash
# select fixture: a git-tracked backlog with mixed live statuses and one
# archived task. task_select must consider only eligible live tasks
# (open/checked/ready), apply the user's api scope narrowing before
# ranking, prefer the viable bug fix, and leave the tree unchanged.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/tasks/evals/fixtures/_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

emit_task() { # <path> <description> <scope> <status> <title> <body>
  cat > "$1" <<EOF
---
description: $2
scope: "$3"
created: $now
updated: $now
status: $4
reported-by: Test User
---

# $5

$6
EOF
}

emit_task "$proj/tasks/api_auth-bug.md" \
  "fix duplicate login redirects in the public API auth middleware" \
  "api" \
  "ready" \
  "Fix duplicate login redirects" \
  "## Goal

Fix a bug where expired API sessions trigger duplicate login redirects.

## Context

The bug is reproducible locally and affects public API clients.

## Approach

Update the auth middleware redirect branch and add a focused regression test.

## Acceptance

- Expired API sessions produce one redirect response."

emit_task "$proj/tasks/api_schema-cleanup.md" \
  "clean up public API schema naming for generated clients" \
  "api" \
  "open" \
  "Clean up API schema naming" \
  "## Goal

Rename inconsistent schema fields for generated clients.

## Context

This improves maintainability but needs compatibility decisions.

## Approach

Review generated clients before choosing the rename shape.

## Acceptance

- Generated clients use consistent schema names."

emit_task "$proj/tasks/infra_metrics-refresh.md" \
  "refresh infrastructure metrics dashboards" \
  "infra" \
  "ready" \
  "Refresh metrics dashboards" \
  "## Goal

Refresh stale infrastructure dashboards.

## Context

The work is useful maintenance but outside the api scope.

## Approach

Update dashboard labels and snapshots.

## Acceptance

- Dashboard labels match the current services."

emit_task "$proj/tasks/api_finished-docs.md" \
  "document already implemented public API behavior" \
  "api" \
  "implemented" \
  "Document implemented API behavior" \
  "## Goal

Document behavior that has already been implemented.

## Context

This task is not eligible for next-work selection.

## Approach

Audit then finish the task.

## Acceptance

- Documentation exists."

emit_task "$proj/tasks/archive/api_old-bug.md" \
  "fix an archived API bug task" \
  "api" \
  "finished" \
  "Archived API bug" \
  "## Goal

Archived work stays out of task_select candidates."
perl -0pi -e 's/(status: finished\nreported-by: Test User\n)/$1implemented-by: Test User\n/' "$proj/tasks/archive/api_old-bug.md"

git_commit_all "$proj" "seed: mixed backlog for task_select"

echo "select sandbox staged at $proj"
