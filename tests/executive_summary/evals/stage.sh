#!/usr/bin/env bash
# stage.sh — stage one executive_summary eval and print the agent-ready inputs.
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
# The staged project holds source.md (the document to summarize) and
# forbidden.txt (terms a faithful summary must not invent). The worker writes
# summary.md beside them.

set -euo pipefail

eval_id="${1:?eval id required (policy_brief|technical_report)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/executive_summary_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$eval_id" in
  policy_brief)
    "$HERE/fixtures/policy_brief/setup.sh" "$target/proj" >/dev/null
    prompt="Summarize the document in source.md."
    ;;
  technical_report)
    "$HERE/fixtures/technical_report/setup.sh" "$target/proj" >/dev/null
    prompt="Summarize the report in source.md for an executive reader."
    ;;
  *)
    printf 'unknown eval id: %s\n' "$eval_id" >&2
    exit 2
    ;;
esac

printf 'sandbox_proj=%q\n' "$target/proj"
printf 'prompt=%q\n' "$prompt"
