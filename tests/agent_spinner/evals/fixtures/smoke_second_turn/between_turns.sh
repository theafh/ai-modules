#!/usr/bin/env bash
# between_turns.sh <sandbox_target> <sandbox_proj>
#
# Runs between the two turns. The second token is staged here, after the first
# turn has completed, so a second turn can only report it by resuming.

set -euo pipefail

target="${1:?sandbox target required}"
proj="${2:?sandbox proj required}"

printf '%s\n%s\n' "$target" "$proj" > "$target/between_args.txt"
printf 'SMOKE_TURN2_9M2X\n' > "$proj/second_token.txt"
