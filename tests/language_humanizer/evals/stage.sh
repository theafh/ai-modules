#!/usr/bin/env bash
# stage.sh — stage one language_humanizer eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Valid eval ids:
#   fidelity_padded    rewrite path, padded draft, nine ledger items
#   compression_trap   rewrite path, transition-carried argument + hedge
#   write_path         write path, unordered notes, five ledger items
#
# Prints name=value lines on stdout, each value already quoted with
# printf %q so the block is safe to `eval`:
#
#   sandbox_proj=<abs path to the project the skill should operate in>
#   source_file=<abs path to the fixture document inside that project>
#   skill_name=language_humanizer
#   skill_path=<abs path to the skill's SKILL.md>
#   prompt=<the user prompt to feed the agent>
#
# Run the agent with $sandbox_proj as its working directory. A pristine copy
# of the fixture is kept at $target/.fixture_pristine so grade.py can prove
# the skill left the source document untouched.

set -euo pipefail

eval_id="${1:?eval id required (fidelity_padded|compression_trap|write_path)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/lh_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
skill_path="$REPO_ROOT/plugins/ai_editorial/skills/language_humanizer/SKILL.md"
skill_name="language_humanizer"

case "$eval_id" in
  fidelity_padded)
    sandbox_proj="$("$HERE/fixtures/fidelity_padded/setup.sh" "$target")"
    source_file="$sandbox_proj/draft.md"
    prompt="The file draft.md is our Q1 checkout status update. Rewrite it so the engineering leads it goes to can act on it after a single read."
    ;;
  compression_trap)
    sandbox_proj="$("$HERE/fixtures/compression_trap/setup.sh" "$target")"
    source_file="$sandbox_proj/draft.md"
    prompt="Rewrite draft.md so the leadership team reading it before Monday's review understands it on the first pass."
    ;;
  write_path)
    sandbox_proj="$("$HERE/fixtures/write_path/setup.sh" "$target")"
    source_file="$sandbox_proj/notes.md"
    prompt="notes.md is my raw whiteboard dump from the incident retro. Turn it into a follow-ups document the on-call team can actually act on."
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

cp "$source_file" "$target/.fixture_pristine"

printf 'sandbox_proj=%q\n' "$sandbox_proj"
printf 'source_file=%q\n'  "$source_file"
printf 'skill_name=%q\n'   "$skill_name"
printf 'skill_path=%q\n'   "$skill_path"
printf 'prompt=%q\n'       "$prompt"
