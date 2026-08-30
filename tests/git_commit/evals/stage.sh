#!/usr/bin/env bash
# stage.sh — stage one git_commit eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints three name=value lines on stdout, each value already quoted
# with printf %q so the lines are safe to `eval`:
#
#   sandbox_repo=<absolute path to the git repo the skill should commit in>
#   skill_path=<absolute path to the SKILL.md the agent should load>
#   prompt=<the user prompt to feed the agent>
#
# Layout: every eval stages under $target as
#   $target/repo                   the git repo the agent commits in
#   $target/skill_under_test/      (eval 5 only) per-sandbox skill copy
#   $target/.eval_started_at       marker containing the staged HEAD SHA;
#                                   grade.sh uses it for the
#                                   "new commit landed" and "no TMPDIR
#                                   context-file straggler" checks
#
# For evals 1..4, 6, 7 skill_path is the real plugin skill. Eval 5 uses a
# per-sandbox stubbed copy (see fixtures/script_failure/setup.sh). Evals
# 6 and 7 additionally launch a detached background writer inside their
# fixture to simulate a concurrent session editing the same tree during
# the agent's run (see fixtures/concurrent_drift, fixtures/ambiguous_drift).

set -euo pipefail

eval_id="${1:?eval id required (1..7)}"
target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/git_commit_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/git_commit/SKILL.md"

case "$eval_id" in
  1)
    "$HERE/fixtures/single_file/setup.sh"     "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit my changes."
    ;;
  2)
    "$HERE/fixtures/multi_file/setup.sh"      "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  3)
    "$HERE/fixtures/mixed_state/setup.sh"     "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  4)
    "$HERE/fixtures/large_changeset/setup.sh" "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  5)
    # The script_failure fixture stages $target/repo and
    # $target/skill_under_test itself and drops the marker too. We
    # mirror the marker behavior below for the other evals.
    "$HERE/fixtures/script_failure/setup.sh"  "$target" >/dev/null
    skill_path="$target/skill_under_test/SKILL.md"
    prompt="Commit."
    ;;
  6)
    "$HERE/fixtures/concurrent_drift/setup.sh" "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  7)
    "$HERE/fixtures/ambiguous_drift/setup.sh"  "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  *)
    echo "unknown eval id: $eval_id (valid: 1..7)" >&2
    exit 2
    ;;
esac

sandbox_repo="$target/repo"

# Marker captures the staged HEAD SHA so grade.sh can confirm the
# agent's commit is genuinely new (and HEAD^ == staged HEAD).
if [[ "$eval_id" != "5" ]]; then
  git -C "$sandbox_repo" rev-parse HEAD > "$target/.eval_started_at"
else
  # Eval 5's fixture already created an empty marker; overwrite with
  # the staged HEAD SHA so grading works the same way.
  git -C "$sandbox_repo" rev-parse HEAD > "$target/.eval_started_at"
fi

printf 'sandbox_repo=%s\n' "$(printf %q "$sandbox_repo")"
printf 'skill_path=%s\n'   "$(printf %q "$skill_path")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
