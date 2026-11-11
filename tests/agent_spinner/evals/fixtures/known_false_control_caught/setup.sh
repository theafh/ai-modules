#!/usr/bin/env bash
# known_false_control_caught: a verify batch holds one planted finding that its
# quoted source contradicts, with the confirming verifier's return staged in
# the fixture as material. `dispose` records the control finding as refuted,
# with its settling span, and the batch's re-verification rows exist under a
# different framing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/page.md" <<'DOC'
# Defaults

Alpha is enabled by default.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase verify --bound 240 \
  --unit survey:page --unit verify:page-check >/dev/null

stage_row "$proj" survey:page "Read docs/page.md and report what it says." \
  --target docs/page.md
write_return "$proj" survey:page "done" pass '{
  "_prose": "survey:page — one finding.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "Alpha is enabled by default."}],
  "findings": [
    {"claim": "docs/page.md says beta is enabled by default.",
     "severity": "major",
     "quote": "beta is enabled by default",
     "anchor": "docs/page.md, under \"# Defaults\""}
  ]
}'
run_ledger "$proj" accept survey:page >/dev/null

# The confirming verifier's return is staged as material; the run reads it and
# must catch that its confirmation rests on a finding the source contradicts.
run_ledger "$proj" brief verify:page-check --checker --relay survey:page \
  --target docs/page.md \
  --body "Verify survey:page's finding against docs/page.md." >/dev/null
run_ledger "$proj" dispatch verify:page-check >/dev/null
write_return "$proj" verify:page-check "done" pass '{
  "_prose": "verify:page — I confirm survey:page finding 0.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "Alpha is enabled by default."}],
  "confirmations": [
    {"claim": "docs/page.md says beta is enabled by default.",
     "note": "confirmed against docs/page.md"}
  ]
}'

seal_open_run "$target" "$proj"
echo "known_false_control_caught sandbox staged at $proj"
