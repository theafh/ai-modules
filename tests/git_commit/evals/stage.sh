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
#   skill_path=<absolute path to this eval's git_commit SKILL.md: the
#              plugin source, or the fixture's edited copy>
#   prompt=<the user prompt to feed the agent>
#
# Layout: every eval stages under $target as
#   $target/repo                   the git repo the agent commits in
#   $target/skill_under_test/      (evals 5, 6, 7) per-sandbox skill copy
#   $target/.eval/baseline_captured  (evals 6, 7) prepare-success marker
#                                   the detached writer waits on
#   $target/.eval_started_at       marker containing the staged HEAD SHA;
#                                   grade.sh uses it for the
#                                   "new commit landed" and "no TMPDIR
#                                   context-file straggler" checks
#
# For evals 1..4, 8..9 skill_path is the real plugin skill. Eval 5 uses a
# per-sandbox stubbed copy (see fixtures/script_failure/setup.sh). Evals
# 6 and 7 use a per-sandbox copy whose prepare_commit_context.sh touches
# .eval/baseline_captured on success, plus a marker-gated detached writer
# that stands in for a concurrent session (see fixtures/concurrent_drift,
# fixtures/ambiguous_drift). Evals 8 and 9 plant an agent-directed
# pre-commit obligation in a sandbox AGENTS.md and observe whether the
# skill's pre-flight relevance test ran it (see fixtures/obligation_skip,
# fixtures/obligation_run).
#
# run.py micro-deploys git_commit and copies every file an edited copy adds
# or changes onto the deployed skill (micro_deploy.overlay_fixture_edits), so
# its worker loads the deployed SKILL.md. An operator-driven run loads
# skill_path directly.

set -euo pipefail

eval_id="${1:?eval id required (1..9)}"
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
    # concurrent_drift stages $target/repo and $target/skill_under_test
    # (prepare wrapped to touch .eval/baseline_captured) plus a
    # marker-gated writer. Mirror eval 5's skill_path wiring.
    "$HERE/fixtures/concurrent_drift/setup.sh" "$target" >/dev/null
    skill_path="$target/skill_under_test/SKILL.md"
    prompt="Commit."
    ;;
  7)
    "$HERE/fixtures/ambiguous_drift/setup.sh" "$target" >/dev/null
    skill_path="$target/skill_under_test/SKILL.md"
    prompt="Commit."
    ;;
  8)
    "$HERE/fixtures/obligation_skip/setup.sh"  "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  9)
    "$HERE/fixtures/obligation_run/setup.sh"   "$target/repo" >/dev/null
    skill_path="$SKILL_MD"
    prompt="Commit."
    ;;
  *)
    echo "unknown eval id: $eval_id (valid: 1..9)" >&2
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
