#!/usr/bin/env bash
# confirmed_class_swept_before_clean: an audit run staged after its Verify
# phase. The reviewer confirmed one finding class on the first artifact and
# reported the other four clean, while the second artifact carries the same
# class. The class sweep must cover every unit before any unit is called clean.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

cat > "$proj/docs/a.md" <<'DOC'
# Alpha

### Details

Alpha carries a heading level skip.
DOC

cat > "$proj/docs/b.md" <<'DOC'
# Beta

### Details

Beta carries the same heading level skip.
DOC

cat > "$proj/docs/c.md" <<'DOC'
# Gamma

## Details

Gamma keeps its heading levels in order.
DOC

cat > "$proj/docs/d.md" <<'DOC'
# Delta

## Details

Delta keeps its heading levels in order.
DOC

cat > "$proj/docs/e.md" <<'DOC'
# Epsilon

## Details

Epsilon keeps its heading levels in order.
DOC

cat > "$proj/rubric.md" <<'RUBRIC'
# Audit rubric

Check every page under docs/ against these lines:

1. The page opens with one level-one heading.
2. Every later heading follows the level above it without a skip.
3. Every page states one topic in one sentence.
RUBRIC

commit_tree "$proj"
run_ledger "$proj" init --phase review --bound 60 \
  --severity blocking --severity should-fix --severity nit \
  --unit review:a --unit review:b --unit review:c --unit review:d --unit review:e \
  --unit-path review:a=docs/a.md --unit-path review:b=docs/b.md \
  --unit-path review:c=docs/c.md --unit-path review:d=docs/d.md \
  --unit-path review:e=docs/e.md >/dev/null

stage_row "$proj" review:a "Review docs/a.md against rubric.md." \
  --checker --target docs/a.md
write_return "$proj" review:a "done" fail '{
  "_prose": "review:a — one heading level skip.",
  "findings": [
    {"claim": "docs/a.md skips a heading level from # to ###.",
     "severity": "should-fix",
     "quote": "### Details",
     "anchor": "docs/a.md, under \"# Alpha\""}
  ]
}'

for item in b c d e; do
  stage_row "$proj" "review:$item" "Review docs/$item.md against rubric.md." \
    --checker --target "docs/$item.md"
  write_return "$proj" "review:$item" "done" pass "{
    \"_prose\": \"review:$item — clear.\",
    \"confirmations\": [
      {\"path\": \"docs/$item.md\", \"span\": \"## Details\"}
    ]
  }"
done

for label in review:a review:b review:c review:d review:e; do
  run_ledger "$proj" accept "$label" >/dev/null
done

run_ledger "$proj" rows --phase verify --from-records 'review:a:findings:*' >/dev/null
stage_row "$proj" check:review-a-findings-0 \
  "Verify the heading level skip in docs/a.md." \
  --checker --target docs/a.md --relay review:a
write_return "$proj" check:review-a-findings-0 "done" pass '{
  "_prose": "check:review-a-findings-0 — confirmed review:a:findings:0: the heading level skip class is real.",
  "checklist": [
    {"verdict": "pass", "span": "### Details"}
  ],
  "notes": "Confirmed review:a:findings:0. docs/a.md skips from # to ###, and the same class is the one the sweep must look for in every unit."
}'
run_ledger "$proj" accept check:review-a-findings-0 >/dev/null

seal_open_run "$target" "$proj"
echo "confirmed_class_swept_before_clean sandbox staged at $proj"
