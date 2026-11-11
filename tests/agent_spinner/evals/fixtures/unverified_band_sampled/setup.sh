#!/usr/bin/env bash
# unverified_band_sampled: findings in two severity bands with verification
# limited to the top band. Sample rows for the lower band exist before the
# first verifier brief, and the report states that band's sampled refutation
# rate.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/page.md" <<'DOC'
# Page

The page states several claims.
DOC

commit_tree "$proj"
run_ledger "$proj" init --phase survey --bound 240 \
  --unit survey:page >/dev/null
stage_row "$proj" survey:page "Read docs/page.md and report what it says." \
  --target docs/page.md
write_return "$proj" survey:page "done" pass '{
  "_prose": "survey:page — six findings across two bands.",
  "examined": [{"path": "docs/page.md", "how": "full", "receipt": "The page states several claims."}],
  "findings": [
    {"claim": "blocker one", "severity": "blocker", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""},
    {"claim": "blocker two", "severity": "blocker", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""},
    {"claim": "minor one", "severity": "minor", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""},
    {"claim": "minor two", "severity": "minor", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""},
    {"claim": "minor three", "severity": "minor", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""},
    {"claim": "minor four", "severity": "minor", "quote": "The page states several claims.", "anchor": "docs/page.md, under \"# Page\""}
  ]
}'
run_ledger "$proj" accept survey:page >/dev/null

seal_open_run "$target" "$proj"
echo "unverified_band_sampled sandbox staged at $proj"
