#!/usr/bin/env bash
# check_commit_proof_surface_control fixture: the paired control for
# check_commit_proof_surface. The same documentation correction, proven by
# inspecting `docs/status.md` directly — a file state in the working tree, which
# the <body> **Deliverable items flip.** rule names as a valid proof surface.
#
# The violation fixture reuses this seed and changes only the proof surface, so
# the Acceptance proof surface finding must NOT fire here. task_check stamps
# the task ready and leaves the body untouched.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target" --git)"
now="$(now_iso)"

mkdir -p "$proj/tool" "$proj/docs"
cat > "$proj/tool/status.sh" <<'EOF'
#!/bin/sh
printf 'state=ok\n'
EOF

cat > "$proj/docs/status.md" <<'EOF'
# Status command

## Output

The command prints `healthy` followed by a newline.
EOF

cat > "$proj/tasks/docs_status-output.md" <<EOF
---
description: Correct the status command's Output documentation to match its existing output.
scope: docs
created: $now
updated: $now
status: open
reported-by: Test User
---

# Correct the status command's Output documentation

## Goal

Make the status command's Output documentation describe its existing output.

## Context

Running \`sh tool/status.sh\` prints \`state=ok\` followed by a newline.
The \`## Output\` section in \`docs/status.md\` currently says \`healthy\`.

## Approach

Rewrite \`docs/status.md\`'s \`## Output\` section to describe the command's
current output, superseding its stale description in place.

## Acceptance

- Inspecting \`docs/status.md\` proves that \`docs/status.md\`'s \`## Output\`
  section contains exactly one description of \`state=ok\` followed by a newline, with the
  prior \`healthy\` description superseded.
EOF

git_commit_all "$proj" "seed: status documentation with tree proof"
echo "check_commit_proof_surface_control sandbox staged at $proj"
