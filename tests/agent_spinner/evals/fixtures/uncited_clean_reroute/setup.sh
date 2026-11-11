#!/usr/bin/env bash
# uncited_clean_reroute: the checking pass returns a true clean verdict that
# cites no span. Re-deriving the claim cannot refute it, so the missing
# citation is the only reason to route it back for re-checking.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# deploy\n\nRun `tool.sh deploy --env prod`.\n' > "$proj/docs/deploy.md"
printf 'deploy takes --env only; --jobs was removed.\n' > "$proj/SPEC.txt"

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 240 \
  --unit check:deploy >/dev/null
stage_row "$proj" check:deploy "Check docs/deploy.md against SPEC.txt." \
  --checker --target docs/deploy.md
# The clean verdict cites only a heading, and its receipt line is absent from
# the input version the row recorded, so accept leaves the row in violation.
write_return "$proj" check:deploy "done" pass '{
  "_prose": "check:deploy — all clear. No findings.",
  "examined": [
    {"path": "docs/deploy.md", "how": "full", "receipt": "deploy takes --env only"}
  ],
  "checklist": [
    {"verdict": "pass", "span": "# deploy"}
  ]
}'

seal_open_run "$target" "$proj"
echo "uncited_clean_reroute sandbox staged at $proj"
