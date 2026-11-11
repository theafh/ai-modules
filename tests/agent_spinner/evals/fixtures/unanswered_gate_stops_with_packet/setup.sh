#!/usr/bin/env bash
# unanswered_gate_stops_with_packet: the request states a size guideline the
# run's own estimate exceeds, and leaves the resulting ask unanswered. No item
# brief is dispatched, the report carries a decision packet with every field,
# and the run ends at the gate with a STOP marker and an open unanswered gate.

set -euo pipefail
THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../_common.sh
. "$THIS_DIR/../_common.sh"

target="${1:?target dir required}"
proj="$(new_project "$target")"
mkdir -p "$proj/docs"

for n in $(seq -w 1 30); do
  printf '# page %s\n\nRun `tool.sh page%s`.\n' "$n" "$n" \
    > "$proj/docs/page$n.md"
done

cat > "$proj/template.md" <<'DOC'
# Template

## Purpose

One sentence saying what the command does.

## Usage

One example of the command with its flags.
DOC

seal "$target" "$proj"
echo "unanswered_gate_stops_with_packet sandbox staged at $proj"
