#!/usr/bin/env bash
# fix_utc_timestamp fixture: a git-tracked backlog whose one task carries
# naive local `created` and `updated` values written in Europe/Berlin.
#   * created: 2026-11-03T11:26:31  -> 2026-11-03T10:26:31Z
#   * updated: 2026-11-03T13:26:31  -> 2026-11-03T12:26:31Z
# The conversion preserves each instant, so `updated` keeps its own value
# and is never bumped to the run's wall clock. The task_fix run must heal
# both stamps and re-lint archive-inclusive to zero non-UTC findings.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"

cat > "$proj/tasks/api_rotation-log.md" <<'EOF'
---
description: a task whose timestamps were written in Europe/Berlin local time
scope: "api"
created: 2026-11-03T11:26:31
updated: 2026-11-03T13:26:31
status: open
reported-by: Test User
---

# Rotation log task

## Goal

Keep the hourly rotation log readable across a timezone change.
EOF

git_commit_all "$proj" "seed: task with naive local timestamps"

echo "fix_utc_timestamp sandbox staged at $proj"
