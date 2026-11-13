#!/usr/bin/env bash
# leading_option_objection_in_packet: an option-panel run staged after its
# Refute phase. Three designers, two judges who rank OPTION_QUEUE first, and
# three refuters whose facts refuter refutes a load-bearing claim of that
# leading option with a citation. The run must finish, surface the objection in
# its decision packet, and report it without choosing an option.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/src" "$proj/docs"

cat > "$proj/src/cache.py" <<'PY'
"""The shipped read-through cache."""

CAPACITY = 1000


def get(key, load):
    value = load(key)
    return value
PY

cat > "$proj/docs/design.md" <<'DOC'
# Candidate design

Replace the read-through cache with a bounded write-through queue of 1000
entries. The design claims the queue halves p99 latency because every read
becomes a local lookup.
DOC

cat > "$proj/src/queue_design.py" <<'PY'
"""The uncommitted candidate: a bounded write-through queue."""

CAPACITY = 1000
PY

commit_tree "$proj"

# The candidate is uncommitted, so the base snapshot holds the shipped design
# alone. The designers read these copies.
run_ledger "$proj" init --phase design --bound 240 \
  --unit design:alpha --unit design:beta --unit design:gamma \
  --unit judge:impact --unit judge:cost \
  --unit refute:facts --unit refute:reasoning --unit refute:consequences \
  >/dev/null
run_ledger "$proj" snapshot base --base src/cache.py docs/design.md >/dev/null

stage_row "$proj" design:alpha \
  "Read the base snapshot and write the option set for the cache change."
write_return "$proj" design:alpha "done" pass '{
  "_prose": "design:alpha — OPTION_QUEUE, OPTION_CACHE, OPTION_ASYNC.",
  "notes": "OPTION_QUEUE replaces the cache with a bounded write-through queue. OPTION_CACHE keeps the read-through cache. OPTION_ASYNC adds an async refresh."
}'
run_ledger "$proj" accept design:alpha >/dev/null

stage_row "$proj" design:beta \
  "Read the base snapshot and write the option set for the cache change."
write_return "$proj" design:beta "done" pass '{
  "_prose": "design:beta — the same three options, costed from the shipped calls.",
  "notes": "OPTION_QUEUE has the best stated latency and the largest coverage regression. OPTION_CACHE has no regression. OPTION_ASYNC costs a new worker."
}'
run_ledger "$proj" accept design:beta >/dev/null

stage_row "$proj" design:gamma \
  "Read the base snapshot and write the option set for the cache change."
write_return "$proj" design:gamma "done" pass '{
  "_prose": "design:gamma — an invite-your-own option and the wrong-call angle.",
  "notes": "The change is the wrong call while the current cache meets the target. OPTION_QUEUE is the strongest of the shipped options."
}'
run_ledger "$proj" accept design:gamma >/dev/null

stage_row "$proj" judge:impact "Score the full option set on impact."
write_return "$proj" judge:impact "done" pass '{
  "_prose": "Ranking: 1. OPTION_QUEUE, 2. OPTION_ASYNC, 3. OPTION_CACHE.",
  "notes": "OPTION_QUEUE ranks first on impact. Its strongest objection is that the latency claim rests on an unbounded queue, and the design bounds it at 1000 entries."
}'
run_ledger "$proj" accept judge:impact >/dev/null

stage_row "$proj" judge:cost "Score the full option set on cost."
write_return "$proj" judge:cost "done" pass '{
  "_prose": "Ranking: 1. OPTION_QUEUE, 2. OPTION_CACHE, 3. OPTION_ASYNC.",
  "notes": "OPTION_QUEUE ranks first on cost as well. The bounded queue drops the oldest entries under pressure."
}'
run_ledger "$proj" accept judge:cost >/dev/null

stage_row "$proj" refute:facts "Test the judges' leading claims against the sources."
write_return "$proj" refute:facts "done" pass '{
  "_prose": "refute:facts — the leading claim does not survive its own design.",
  "findings": [
    {"claim": "OPTION_QUEUE halves p99 latency only with an unbounded queue, and the design bounds it at 1000 entries.",
     "severity": "major",
     "quote": "The design claims the queue halves p99 latency because every read becomes a local lookup.",
     "anchor": "docs/design.md"}
  ]
}'
run_ledger "$proj" accept refute:facts >/dev/null

stage_row "$proj" refute:reasoning "Test the judges' reasoning for the leading option."
write_return "$proj" refute:reasoning "done" pass '{
  "_prose": "refute:reasoning — the ranking arithmetic holds for the three shipped options."
}'
run_ledger "$proj" accept refute:reasoning >/dev/null

stage_row "$proj" refute:consequences "Test the consequences of the leading option."
write_return "$proj" refute:consequences "done" pass '{
  "_prose": "refute:consequences — the coverage regression is stated, not hidden."
}'
run_ledger "$proj" accept refute:consequences >/dev/null

seal_open_run "$target" "$proj"
echo "leading_option_objection_in_packet sandbox staged at $proj"
