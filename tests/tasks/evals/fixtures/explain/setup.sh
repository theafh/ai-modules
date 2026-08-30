#!/usr/bin/env bash
# explain fixture: a git-tracked backlog with one archived task whose
# Goal / Context / Approach make the what, why, and how beats distinct.
# task_explain must orient on the archived task and leave the tree clean.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tests/tasks/evals/fixtures/_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/tasks/archive/api_retry-after-header.md" <<EOF
---
description: document the API rate-limit Retry-After header behavior for closed client-facing work
scope: plugins/ai_dev
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Explain Retry-After header behavior

## Goal

Add client-facing documentation for the Retry-After header emitted by the API rate limiter.

## Context

Clients currently see HTTP 429 responses without a compact task-level explanation of the header contract. The task was archived after the documentation shipped, but readers still need to understand the intent behind the closed work.

## Approach

Read the API rate-limit documentation, rewrite the header passage in place, and add one example response that shows the Retry-After value next to HTTP 429.

## Acceptance

- The explanation names the documentation goal.
- The explanation names the client-orientation motivation.
- The explanation names the rewrite-and-example approach.
EOF

git_commit_all "$proj" "seed: archived task for task_explain"

echo "explain sandbox staged at $proj"
