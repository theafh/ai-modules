#!/usr/bin/env bash
# stage.sh — stage one task_create open-decision eval and print the
# agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Valid eval ids:
#   reconcile-recorded        the fork every evidence tier settles: the written
#                             task carries no open decision and records the
#                             resolution in the body
#   labeled-why-open          the fork no tier settles: exactly one labeled
#                             "Open decision:" with options, a suggested
#                             default, and the why-open clause — surfaced to
#                             the user, not left resting in the file
#   guardrail-bound-surface   the fork whose every path crosses a guardrail
#                             boundary: labeled and surfaced the same way,
#                             never auto-resolved
#
# Prints name=value lines on stdout, each value already quoted with printf %q
# so the block is safe to `eval`:
#
#   sandbox_proj=<abs path to the project the skill should operate in>
#   skill_name=<the skill the agent should load>
#   skill_path=<abs path to that skill's SKILL.md>
#   prompt=<the user prompt to feed the agent>
#
# Run the agent with $sandbox_proj as its working directory so the skill's
# discover_tasks.sh resolves the sandbox and never the real repo. A marker file
# $target/.eval_started_at records the run-start epoch; grade.sh uses it for
# created-timestamp tolerance and isolation checks.

set -euo pipefail

eval_id="${1:?eval id required (reconcile-recorded|labeled-why-open|guardrail-bound-surface)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/task_create_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILLS="$REPO_ROOT/plugins/ai_dev/skills"

skill_name="task_create"

case "$eval_id" in
  reconcile-recorded)
    "$HERE/fixtures/reconcile-recorded/setup.sh" "$target" >/dev/null
    prompt="Make a task for adding unit tests to the pure helpers in src/report/render.py — format_severity and truncate_cell. That module imports the chartkit backend at module scope, so the tests need some way to get at those helpers."
    ;;
  labeled-why-open)
    "$HERE/fixtures/labeled-why-open/setup.sh" "$target" >/dev/null
    prompt="Make a task for adding retry with exponential backoff to the outbound webhook sender in src/hooks/sender.py. Whether an endpoint that keeps failing gets auto-disabled after a run of consecutive failures, or just keeps getting retried forever, is a call I want to make myself."
    ;;
  guardrail-bound-surface)
    "$HERE/fixtures/guardrail-bound-surface/setup.sh" "$target" >/dev/null
    prompt="Make a task to add coloured severity markers to the report command's output in src/report/cli.py, so warnings and errors stand out from the ordinary rows."
    ;;
  *)
    echo "unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

sandbox_proj="$target/proj"
skill_path="$SKILLS/$skill_name/SKILL.md"

# Marker = run-start epoch. grade.sh reads it for created-timestamp tolerance
# and "nothing newer outside the sandbox" isolation checks.
date +%s > "$target/.eval_started_at"

printf 'sandbox_proj=%s\n' "$(printf %q "$sandbox_proj")"
printf 'skill_name=%s\n'   "$(printf %q "$skill_name")"
printf 'skill_path=%s\n'   "$(printf %q "$skill_path")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
