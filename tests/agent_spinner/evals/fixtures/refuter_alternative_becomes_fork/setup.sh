#!/usr/bin/env bash
# refuter_alternative_becomes_fork: a disputed-claim run staged after its
# Refute phase. One refuter's accepted return carries an alternative reading of
# the timeout figure with its derivation, and the other supports the proposed
# edit. The alternative rests on the sweep's provenance class: the configuration
# is a derived page generated from the specification, so its value is drift
# rather than a better-supported figure. The run must surface the alternative as
# a fork and write nothing.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs" "$proj/src" "$proj/tools"

cat > "$proj/docs/spec.md" <<'DOC'
# Timeouts

The service timeout is 30 seconds.
DOC

cat > "$proj/docs/notes.md" <<'DOC'
# Notes

The service timeout is 30 seconds, as the specification says.
DOC

cat > "$proj/src/config.ini" <<'DOC'
# Generated from docs/spec.md by tools/render_config.py. Do not edit.
[timeouts]
read_timeout = 45
DOC

cat > "$proj/tools/render_config.py" <<'PY'
"""Render src/config.ini from docs/spec.md."""

SPEC = "docs/spec.md"
OUT = "src/config.ini"
PY

commit_tree "$proj"

run_ledger "$proj" init --phase refute --bound 240 \
  --unit sweep:docs --unit sweep:src \
  --unit derive:question \
  --unit refute:edit1 --unit refute:edit2 >/dev/null
run_ledger "$proj" snapshot sources docs/spec.md docs/notes.md src/config.ini >/dev/null

stage_row "$proj" sweep:docs "Sweep docs/ for every timeout occurrence."
write_return "$proj" sweep:docs "done" pass '{
  "_prose": "sweep:docs — docs/spec.md and docs/notes.md state 30 seconds in finished prose."
}'
run_ledger "$proj" accept sweep:docs >/dev/null

stage_row "$proj" sweep:src "Sweep src/ for every timeout occurrence."
write_return "$proj" sweep:src "done" pass '{
  "_prose": "sweep:src — src/config.ini sets read_timeout to 45 in a derived page generated from docs/spec.md.",
  "notes": "Provenance class: derived page. The header names tools/render_config.py as the generator."
}'
run_ledger "$proj" accept sweep:src >/dev/null

stage_row "$proj" derive:question "Derive the timeout value from the sources."
write_return "$proj" derive:question "done" pass '{
  "_prose": "derive:question — the configuration reads 45 seconds; the specification reads 30.",
  "notes": "The sources disagree. The configuration is the value the running system reads."
}'
run_ledger "$proj" accept derive:question >/dev/null

stage_row "$proj" refute:edit1 "Test the proposed edit that changes the specification to 45 seconds."
write_return "$proj" refute:edit1 "done" pass '{
  "_prose": "refute:edit1 — the edit is supported: the configuration is what the system reads.",
  "notes": "Change docs/spec.md to 45 seconds."
}'
run_ledger "$proj" accept refute:edit1 >/dev/null

stage_row "$proj" refute:edit2 "Test the proposed edit that changes the specification to 45 seconds."
write_return "$proj" refute:edit2 "done" pass '{
  "_prose": "refute:edit2 — the edit overwrites the source with its derived value.",
  "alternatives": [
    {"reading": "src/config.ini is a derived page generated from docs/spec.md, so its 45 seconds is drift, not a better-supported figure.",
     "derivation": "sweep:src records the configuration as a derived page whose header names tools/render_config.py, so changing docs/spec.md to 45 would overwrite the source with the output of its own generator. Keep 30 and fix the generator instead.",
     "provenance": "derived page, read in the generated configuration header and the sweep provenance class"}
  ]
}'
run_ledger "$proj" accept refute:edit2 >/dev/null

seal_open_run "$target" "$proj"
echo "refuter_alternative_becomes_fork sandbox staged at $proj"
