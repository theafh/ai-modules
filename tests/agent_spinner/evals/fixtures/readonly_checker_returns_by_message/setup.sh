#!/usr/bin/env bash
# readonly_checker_returns_by_message: one written file is checked by a role
# staged with no file-write tool and no shell. The checker returns its block as
# its final message, and the orchestrator relays it into accept --stdin.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# alpha\n\nRun `tool.sh alpha --workers 4`.\n' > "$proj/docs/alpha.md"

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:alpha >/dev/null
run_ledger "$proj" brief check:alpha --checker --target docs/alpha.md \
  --body "Spawn the readonly_checker role with this brief and relay its final message." >/dev/null
run_ledger "$proj" dispatch check:alpha >/dev/null

seal_open_run "$target" "$proj"
echo "readonly_checker_returns_by_message sandbox staged at $proj"
