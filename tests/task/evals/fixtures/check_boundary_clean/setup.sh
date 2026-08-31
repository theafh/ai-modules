#!/usr/bin/env bash
# check_boundary_clean fixture (control): a well-formed, self-sufficient task
# that carries NO `**Out of scope:**` block at all. The Out of scope
# convention is optional, so its absence must raise NO boundary finding at
# check time — presence stays optional and the machinery stays invisible when
# there is nothing to exclude. task_check assesses the task on its other merits
# and stamps a verdict, but no boundary-contradiction issue appears.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
now="$(now_iso)"

cat > "$proj/tasks/cli_exit-code-on-error.md" <<EOF
---
description: Make the report command exit non-zero when it cannot read its input file, so callers detect the failure.
scope: "cli"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Exit non-zero when the report input is unreadable

## Goal

Make the \`report\` command exit with status \`1\` and print a one-line error to stderr when its input file cannot be read, so a calling script detects the failure instead of treating a silent empty run as success.

## Context

\`report\` reads its input file and prints a table. When the file is missing or unreadable it currently prints nothing and exits \`0\`, so callers cannot tell the run failed. The fix is confined to the input-open path.

## Approach

Wrap the input-file open in the \`report\` command: on an \`OSError\`, write \`report: cannot read <path>\` to stderr and exit \`1\`; on success, keep the existing table output.

## Acceptance

- \`report\` on a missing input file exits with status \`1\`.
- The error line \`report: cannot read <path>\` is written to stderr.
- \`report\` on a readable input file still prints the table and exits \`0\`.
EOF

echo "check_boundary_clean sandbox staged at $proj"
