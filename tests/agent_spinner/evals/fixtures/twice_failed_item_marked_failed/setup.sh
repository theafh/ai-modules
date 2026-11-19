#!/usr/bin/env bash
# twice_failed_item_marked_failed: one writer row is at its second attempt. Its
# first return was rejected, and the second return staged here is rejected too,
# so the run must mark the item failed, leave the target untouched, and offer
# the inline redo as the user's choice.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --jobs 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase produce --bound 240 \
  --unit produce:alpha --unit-path produce:alpha=docs/alpha.md >/dev/null
stage_row "$proj" produce:alpha "Rewrite docs/alpha.md to use --workers." \
  --target docs/alpha.md

# First attempt: a return with no END line is refused, and the row becomes a
# contract violation with one recorded rejection.
printf 'produce:alpha — docs/alpha.md is rewritten.\n' \
  > "$proj/.agent_spinner/returns/produce:alpha.md"
run_ledger "$proj" accept produce:alpha >/dev/null 2>&1 || true

# Second attempt: the staged return is refused again, so the ledger marks the
# row failed. The run's job is to report that state, leave the page alone, and
# put the inline redo to the user.
printf 'produce:alpha — second attempt.\n\n```json\n{"label": "produce:alpha", "objections": []}\n```\n\nEND produce:alpha\n' \
  > "$proj/.agent_spinner/returns/produce:alpha.md"
run_ledger "$proj" accept produce:alpha >/dev/null 2>&1 || true

seal_open_run "$target" "$proj"
echo "twice_failed_item_marked_failed sandbox staged at $proj"
