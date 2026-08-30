#!/usr/bin/env bash
# create_scope_trim fixture: an empty backlog. The create prompt asks for a
# --json flag now and names --yaml and --csv as wanted-but-not-now. task_create
# must write ONE task for the --json work and land the trimmed --yaml/--csv
# work in that file's `**Out of scope:**` block — as a deferral naming an owner
# or an explicit rejection, never a silent drop — with no prompt added beyond
# the existing create flow. Nothing to seed beyond the empty project; the
# trimmed work lives only in the prompt.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"

echo "create_scope_trim sandbox staged at $proj"
