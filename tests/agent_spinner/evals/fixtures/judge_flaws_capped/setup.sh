#!/usr/bin/env bash
# judge_flaws_capped: four candidates and a two-judge panel. Each judge return
# holds at most three fatal flaws, each with a span.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/candidates"

for name in one two three four; do
  printf '# Candidate %s\n\nA proposal for the cache layout.\n' "$name" \
    > "$proj/candidates/$name.md"
done

commit_tree "$proj"
run_ledger "$proj" init --phase judge --bound 240 \
  --unit judge:speed --unit judge:cost >/dev/null

for judge in speed cost; do
  run_ledger "$proj" brief "judge:$judge" \
    --body "Score candidates/one.md through candidates/four.md on $judge." >/dev/null
  run_ledger "$proj" dispatch "judge:$judge" >/dev/null
  write_return "$proj" "judge:$judge" "done" pass "{
    \"_prose\": \"judge:$judge — three fatal flaws at most.\",
    \"examined\": [{\"path\": \"candidates/one.md\", \"how\": \"full\", \"receipt\": \"A proposal for the cache layout.\"}],
    \"findings\": [
      {\"claim\": \"candidate one flaw a\", \"severity\": \"major\", \"quote\": \"A proposal for the cache layout.\", \"anchor\": \"candidates/one.md\"},
      {\"claim\": \"candidate two flaw b\", \"severity\": \"minor\", \"quote\": \"A proposal for the cache layout.\", \"anchor\": \"candidates/two.md\"},
      {\"claim\": \"candidate three flaw c\", \"severity\": \"minor\", \"quote\": \"A proposal for the cache layout.\", \"anchor\": \"candidates/three.md\"}
    ]
  }"
done

seal_open_run "$target" "$proj"
echo "judge_flaws_capped sandbox staged at $proj"
