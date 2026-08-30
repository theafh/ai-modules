#!/usr/bin/env bash
# query fixture: a git-tracked backlog with several OPEN tasks across two
# scopes (api, infra) plus one ARCHIVED task. The base `task` skill's
# <query> workflow must list the open tasks grouped by scope and lead with
# them, surfacing the archived entry only if asked — which this prompt is
# not. Read-only: the skill lists, it must not edit or move anything.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

emit_task() { # <path> <description> <scope> <status> <title>
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

## Goal

Placeholder goal for the $5 task.
EOF
}

emit_task "$proj/tasks/api_rate-limit.md"        "rate limit the public API"        "api"   "open" "API rate limiting"
emit_task "$proj/tasks/api_throttle-config.md"   "make the throttle window config"  "api"   "open" "Configurable throttle window"
emit_task "$proj/tasks/infra_grafana-cleanup.md" "tidy the grafana dashboards"      "infra" "open" "Grafana dashboard cleanup"
emit_task "$proj/tasks/archive/api_legacy-auth.md" "remove the legacy auth path"    "api"   "finished" "Remove legacy auth"
perl -0pi -e 's/(status: finished\nreported-by: Test User\n)/$1implemented-by: Test User\n/' "$proj/tasks/archive/api_legacy-auth.md"

git_commit_all "$proj" "seed: three open tasks across two scopes plus one archived"

echo "query sandbox staged at $proj"
