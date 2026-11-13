#!/usr/bin/env bash
# unnarrowed_flag_blocks_deliverable: a research-synthesis run staged after its
# deliverable merge. The flag ledger lists one claim a verifier narrowed, and
# the merged deliverable still states the claim in its original wording. The
# flag-ledger pass must name the entry, and the run either narrows the
# deliverable with its own check or reports the entry as blocking.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/inputs"

cat > "$proj/inputs/a.md" <<'DOC'
# Cache notes

The cache holds at most ten thousand entries.
DOC

cat > "$proj/inputs/b.md" <<'DOC'
# Operator report

Operators report the limit is eight thousand entries under load.
DOC

cat > "$proj/deliverable.md" <<'DOC'
# Cache limit

The cache holds at most ten thousand entries.
DOC

commit_tree "$proj"

run_ledger "$proj" init --phase verify --bound 240 \
  --unit read:alpha --unit read:beta \
  --unit draft:one --unit draft:two --unit draft:three \
  --unit judge:crit1 --unit judge:crit2 \
  --unit verify:limits --unit write:deliverable \
  --unit flagledger:flags >/dev/null

stage_row "$proj" read:alpha "Read inputs/a.md and return tiered facts."
write_return "$proj" read:alpha "done" pass '{
  "_prose": "read:alpha — the cache note states ten thousand entries as read.",
  "notes": "inputs/a.md is finished prose."
}'
run_ledger "$proj" accept read:alpha >/dev/null

stage_row "$proj" read:beta "Read inputs/b.md and return tiered facts."
write_return "$proj" read:beta "done" pass '{
  "_prose": "read:beta — the operator report states eight thousand entries.",
  "notes": "inputs/b.md is finished prose, an outcome report."
}'
run_ledger "$proj" accept read:beta >/dev/null

stage_row "$proj" draft:one "Write the limits angle of the deliverable."
write_return "$proj" draft:one "done" pass '{
  "_prose": "draft:one — the limits section."
}'
run_ledger "$proj" accept draft:one >/dev/null

stage_row "$proj" draft:two "Write the operations angle of the deliverable."
write_return "$proj" draft:two "done" pass '{
  "_prose": "draft:two — the operations section."
}'
run_ledger "$proj" accept draft:two >/dev/null

stage_row "$proj" draft:three "Write the premise-challenge angle of the deliverable."
write_return "$proj" draft:three "done" pass '{
  "_prose": "draft:three — the premise-challenge section."
}'
run_ledger "$proj" accept draft:three >/dev/null

stage_row "$proj" judge:crit1 "Score the draft set on coverage."
write_return "$proj" judge:crit1 "done" pass '{
  "_prose": "Ranking: 1. the merged draft, on coverage."
}'
run_ledger "$proj" accept judge:crit1 >/dev/null

stage_row "$proj" judge:crit2 "Score the draft set on accuracy."
write_return "$proj" judge:crit2 "done" pass '{
  "_prose": "Ranking: 1. the merged draft, on accuracy."
}'
run_ledger "$proj" accept judge:crit2 >/dev/null

stage_row "$proj" verify:limits "Test the cache-limit claim against both sources."
write_return "$proj" verify:limits "done" pass '{
  "_prose": "verify:limits — the ten-thousand figure is narrowed by the operator report.",
  "findings": [
    {"claim": "The cache limit is narrowed to eight thousand entries, not ten thousand.",
     "severity": "major",
     "quote": "Operators report the limit is eight thousand entries under load.",
     "anchor": "inputs/b.md"}
  ]
}'
run_ledger "$proj" accept verify:limits >/dev/null

stage_row "$proj" write:deliverable "Merge the drafts into deliverable.md."
write_return "$proj" write:deliverable "done" pass '{
  "_prose": "write:deliverable — the merged deliverable."
}'
run_ledger "$proj" accept write:deliverable >/dev/null

# The flag ledger names the verifier's finding and the narrowed wording. The
# merged deliverable still carries the original wording.
cat > "$proj/.agent_spinner/flag-ledger.md" <<'FLAGS'
# Flag ledger

- verify:limits:findings:0 | claim: The cache holds at most ten thousand entries. | narrowed to: The cache holds at most eight thousand entries.
FLAGS

# Recorded inputs the flag-ledger pass and any follow-up check may cite.
for rel in deliverable.md .agent_spinner/flag-ledger.md; do
  dest="$proj/.agent_spinner/baseline/inputs/flagledger:flags/$rel"
  mkdir -p "$(dirname "$dest")"
  cp "$proj/$rel" "$dest"
done

seal_open_run "$target" "$proj"
echo "unnarrowed_flag_blocks_deliverable sandbox staged at $proj"
