#!/usr/bin/env bash
# role_depth_recorded: a plan requests a checker at or above its producer's
# effort, and the host returns an observed effort for that checker below the
# producer's. Each roster row carries the requested model and effort and the
# observed values, with unobserved where the host exposed nothing. The close
# flags the checker on its recorded depth, and the report names the flag as a
# narrowing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

printf '# page\n\nRun `tool.sh page --jobs 4`.\n' > "$proj/docs/page.md"

commit_tree "$proj"
run_ledger "$proj" init --phase work --bound 240 \
  --unit produce:page --unit check:page-check \
  --unit-path produce:page=docs/page.md \
  --unit-path check:page-check=docs/page.md >/dev/null

run_ledger "$proj" brief produce:page --target docs/page.md --depth 3 \
  --body "Rewrite docs/page.md to use --workers." >/dev/null
run_ledger "$proj" dispatch produce:page --model host-default --effort high >/dev/null
write_return "$proj" produce:page "done" pass '{
  "_prose": "produce:page — rewrote the page.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "Run `tool.sh page --jobs 4`."}],
  "checklist": [{"verdict": "pass", "span": "Run `tool.sh page --jobs 4`."}]
}'
# The host exposed nothing for this spawn, so both observed values read
# unobserved.
run_ledger "$proj" accept produce:page >/dev/null

run_ledger "$proj" brief check:page-check --checker --relay produce:page \
  --target docs/page.md --depth 1 \
  --body "Check produce:page's rewrite against docs/page.md." >/dev/null
run_ledger "$proj" dispatch check:page-check --model cheap-model --effort low >/dev/null
write_return "$proj" check:page-check "done" pass '{
  "_prose": "check:page-check — PASS.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "Run `tool.sh page --jobs 4`."}],
  "checklist": [{"verdict": "pass", "span": "Run `tool.sh page --jobs 4`."}]
}'
run_ledger "$proj" accept check:page-check \
  --observed-model cheap-model --observed-effort low >/dev/null

seal_open_run "$target" "$proj"
echo "role_depth_recorded sandbox staged at $proj"
