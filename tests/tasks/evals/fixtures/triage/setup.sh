#!/usr/bin/env bash
# triage fixture: a git-tracked backlog with one task seeded with three
# known defects matching the canned task_check report in the prompt:
#   1. an unverifiable acceptance item ("works properly")   -> user ACCEPTS the fix
#   2. a Goal sentence the report wants reworded            -> user REJECTS (stays byte-identical)
#   3. an empty ## Context the report wants pointed at
#      src/api/server.py                                    -> user MODIFIES (docs/api.md instead)
# The numbered-triage apply flow must apply exactly the accepted and
# modified findings, leave the rejected passage untouched, bump updated
# once from the wall clock, and re-lint once at the end.

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

Protect the public API from abusive clients.

## Context

## Approach

Add a fixed-window counter in the request middleware.

## Acceptance

- the rate limiter works properly
EOF

# Real targets for the context pointer, so either choice would resolve:
# the report suggests src/api/server.py, the user redirects to docs/api.md.
mkdir -p "$proj/src/api" "$proj/docs"
cat > "$proj/src/api/server.py" <<'EOF'
# Request middleware lives here; the rate limiter hooks in below.
def handle(request):
    return request
EOF
cat > "$proj/docs/api.md" <<'EOF'
# Public API

## Rate limits

Clients are throttled per minute; rejected requests receive HTTP 429.
EOF

git_commit_all "$proj" "seed: rate-limit task with three known check findings"

echo "triage sandbox staged at $proj"
