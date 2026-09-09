#!/usr/bin/env bash
# check_commit_proof_surface fixture: the same documentation-correction task as
# its control, with the single Acceptance item's proof surface moved onto the
# commit message. Everything else stays identical to the control seed.
#
# The <body> **Deliverable items flip.** rule fixes each item's proof surface in
# the working tree as it stands before any commit, so the commit message is
# never one and the <readiness_checklist> Acceptance proof surface finding must
# fire, routed through Decide or label with a tree-artifact fix. It is the only
# blocking finding, so task_check withholds ready (stamps checked) and leaves
# the body untouched.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
"$THIS_DIR/../check_commit_proof_surface_control/setup.sh" "$target" >/dev/null
proj="$(cd "$target/proj" && pwd)"
task="$proj/tasks/docs_status-output.md"
sed 's/Inspecting `docs\/status.md` proves/Inspecting the commit message proves/' \
    "$task" > "$task.tmp"
mv "$task.tmp" "$task"

git_commit_all "$proj" "seed: status documentation with commit-message proof"
echo "check_commit_proof_surface sandbox staged at $proj"
