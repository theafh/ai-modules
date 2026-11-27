#!/usr/bin/env bash
# stage.sh — stage one spr eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints three name=value lines on stdout, each value already quoted with
# printf %q so the lines are safe to `eval`:
#
#   sandbox_proj=<absolute path to the project holding source.md>
#   prompt=<the user prompt to feed the agent>
#
# The staged project holds source.md (the text to compress) and forbidden.txt
# (terms a faithful SPR must not invent). The worker writes spr.md beside them.

set -euo pipefail

eval_id="${1:?eval id required (priming_basics|memory_systems)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/spr_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$eval_id" in
  priming_basics)
    "$HERE/fixtures/priming_basics/setup.sh" "$target/proj" >/dev/null
    prompt="Turn the text in source.md into an SPR."
    ;;
  memory_systems)
    "$HERE/fixtures/memory_systems/setup.sh" "$target/proj" >/dev/null
    prompt="Compress the text in source.md into an SPR."
    ;;
  *)
    printf 'unknown eval id: %s\n' "$eval_id" >&2
    exit 2
    ;;
esac

printf 'sandbox_proj=%q\n' "$target/proj"
printf 'prompt=%q\n' "$prompt"
