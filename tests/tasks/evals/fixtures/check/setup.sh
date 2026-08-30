#!/usr/bin/env bash
# check fixture: one under-specified open task — vague goal, empty
# Approach and Acceptance. task_check must judge it not-ready and emit a
# General assessment + a non-empty Issues list, without editing the file.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/tasks/api_make-it-better.md" <<EOF
---
description: improve the API somehow
scope: "api"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Make the API better

## Goal

Make the API better and faster and nicer to use.

## Context

## Approach

## Acceptance
EOF

git_commit_all "$proj" "seed: an under-specified task awaiting readiness review"

echo "check sandbox staged at $proj"
