#!/usr/bin/env bash
# between_turns.sh <sandbox_target> <sandbox_proj>
#
# Runs between the two turns. The dispatched writer's return file lands here,
# so only a resumed turn can accept it.

set -euo pipefail

target="${1:?sandbox target required}"
proj="${2:?sandbox proj required}"

. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../_common.sh"

write_return "$proj" produce:alpha "done" pass '{
  "_prose": "produce:alpha — docs/alpha.md is updated."
}'
printf '%s\n' "$target" > "$target/between_args.txt"
