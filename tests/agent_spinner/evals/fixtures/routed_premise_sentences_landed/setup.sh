#!/usr/bin/env bash
# routed_premise_sentences_landed: a closed fidelity run whose plan routed two
# premise sentences, one to each page, while only the first page carries its
# sentence. The post-run checks must fail the second page and the report must
# not claim every routed sentence landed.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/pages"

cat > "$proj/pages/one.md" <<'PAGE'
# Cache eviction

The cache evicts on write, not on read.

The premise that eviction happens on write is worth revisiting.
PAGE

cat > "$proj/pages/two.md" <<'PAGE'
# Cache sizing

The cache is bounded by the configured size.
PAGE

commit_tree "$proj"
run_ledger "$proj" init --phase write --bound 60 \
  --unit write:one --unit write:two \
  --unit-path write:one=pages/one.md --unit-path write:two=pages/two.md >/dev/null

cat > "$proj/.agent_spinner/plan.md" <<'PLAN'
# Fidelity plan

## Routed premise sentences

- pages/one.md: "The premise that eviction happens on write is worth revisiting."
- pages/two.md: "The premise that the cache is unbounded is worth revisiting."
PLAN

for item in one two; do
  stage_row "$proj" "write:$item" "Apply the routed premise sentence to pages/$item.md." \
    --target "pages/$item.md"
  write_return "$proj" "write:$item" "done" pass "{
    \"_prose\": \"write:$item — applied the routed premise sentence.\"
  }"
  run_ledger "$proj" accept "write:$item" >/dev/null
done

tally="$(run_ledger "$proj" close 2>/dev/null || true)"
printf '%s\n' "$tally" > "$proj/.agent_spinner/report.md"
run_ledger "$proj" close >/dev/null

seal_open_run "$target" "$proj"
echo "routed_premise_sentences_landed sandbox staged at $proj"
