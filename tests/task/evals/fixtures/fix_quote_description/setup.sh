#!/usr/bin/env bash
# fix_quote_description fixture: one live task whose unquoted description
# contains a colon followed by a space. task_fix quotes that value and
# leaves the description text and the body unchanged.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

cat > "$proj/tasks/tool_install-floor.md" <<EOF
---
description: Turn make install into environment preparation: declare the runtime
scope: "tool"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Install floor

## Goal

Declare the runtime tools make install prepares.

## Acceptance

- The install target names the runtime tools it prepares.
EOF

git_commit_all "$proj" "seed: unquoted description with a colon"

echo "fix_quote_description sandbox staged at $proj"
