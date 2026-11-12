#!/usr/bin/env bash
# repair_list_keyed_on_severity: an artifact-repair run staged after its Check
# phase. One artifact fails with two should-fix findings on the same path, one
# fails with nits only, and one passes with no findings. The repair list holds
# the first artifact once, keyed on one of its finding records, and the report
# carries the nit-only artifact's findings.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/spec"

cat > "$proj/spec/alpha.md" <<'SPEC'
# Alpha specification

The alpha command accepts --jobs.
SPEC

cat > "$proj/spec/beta.md" <<'SPEC'
# Beta specification

The beta command accepts --dry-run.
SPEC

cat > "$proj/spec/gamma.md" <<'SPEC'
# Gamma specification

The gamma command accepts no flags.
SPEC

commit_tree "$proj"
run_ledger "$proj" init --phase check --bound 60 \
  --severity blocking --severity should-fix --severity nit \
  --unit check:alpha --unit check:beta --unit check:gamma \
  --unit-path check:alpha=spec/alpha.md \
  --unit-path check:beta=spec/beta.md \
  --unit-path check:gamma=spec/gamma.md >/dev/null

stage_row "$proj" check:alpha "Check spec/alpha.md against the shipped alpha command." \
  --checker --target spec/alpha.md
write_return "$proj" check:alpha "done" fail '{
  "_prose": "check:alpha — FAIL with two should-fix findings.",
  "findings": [
    {"claim": "spec/alpha.md names --jobs, which the alpha command no longer accepts.",
     "severity": "should-fix",
     "quote": "The alpha command accepts --jobs.",
     "anchor": "spec/alpha.md, under \"# Alpha specification\""},
    {"claim": "spec/alpha.md omits the --workers flag the alpha command now requires.",
     "severity": "should-fix",
     "quote": "The alpha command accepts --jobs.",
     "anchor": "spec/alpha.md, under \"# Alpha specification\""}
  ]
}'

stage_row "$proj" check:beta "Check spec/beta.md against the shipped beta command." \
  --checker --target spec/beta.md
write_return "$proj" check:beta "done" fail '{
  "_prose": "check:beta — FAIL with nits only.",
  "findings": [
    {"claim": "spec/beta.md writes --dry-run without backticks.",
     "severity": "nit",
     "quote": "The beta command accepts --dry-run.",
     "anchor": "spec/beta.md, under \"# Beta specification\""},
    {"claim": "spec/beta.md ends without a trailing newline sentence.",
     "severity": "nit",
     "quote": "The beta command accepts --dry-run.",
     "anchor": "spec/beta.md, under \"# Beta specification\""}
  ]
}'

stage_row "$proj" check:gamma "Check spec/gamma.md against the shipped gamma command." \
  --checker --target spec/gamma.md
write_return "$proj" check:gamma "done" pass '{
  "_prose": "check:gamma — PASS with no findings."
}'

for label in check:alpha check:beta check:gamma; do
  run_ledger "$proj" accept "$label" >/dev/null
done

seal_open_run "$target" "$proj"
echo "repair_list_keyed_on_severity sandbox staged at $proj"
