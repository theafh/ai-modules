#!/usr/bin/env bash
# stage.sh — stage one git_checkout eval and print the agent-ready inputs.
#
# Usage:
#   stage.sh <eval_id> [target_dir]
#
# Prints three name=value lines on stdout, each value already quoted with
# printf %q so the lines are safe to `eval`:
#
#   sandbox_repo=<absolute path to the clone the skill runs in>
#   skill_path=<absolute path to the plugin source SKILL.md, for a run by hand>
#   prompt=<the eval's user prompt>
#
# evals.json is the one source of each eval's fixture and prompt: the fixture
# stager is the eval's first `files` entry (relative to tests/git_checkout/),
# and the prompt is its `prompt`. run.py loads the micro-deployed SKILL.md
# from that pass's path map rather than skill_path.
#
# Layout under the target directory:
#   $target/repo           the clone under test, the worker's working directory
#   $target/origin.git     its bare origin (plus fork.git for two_remotes_same_name)
#   $target/.eval/         stage-time snapshots grade.sh compares against:
#     branch_before          the branch HEAD named
#     head_before            the commit HEAD resolved to
#     branches_before        every local branch with its tip
#     status_before          git status --porcelain=v1 --untracked-files=all
#     remote_heads           "<remote> <branch> <sha>" for every bare remote

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HARNESS="$(cd "$HERE/.." && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
EVALS="$HERE/evals.json"
SKILL_MD="$REPO_ROOT/plugins/ai_dev/skills/git_checkout/SKILL.md"

valid_ids() {
  jq -r '[.evals[].id | tostring] | join(" ")' "$EVALS"
}

eval_id="${1:?eval id required ($(valid_ids))}"
case "$eval_id" in
  ''|*[!0-9]*)
    echo "unknown eval id: $eval_id (valid: $(valid_ids))" >&2
    exit 2
    ;;
esac

fixture_rel="$(jq -r --argjson id "$eval_id" \
  '.evals[] | select(.id == $id) | .files[0] // empty' "$EVALS")"
prompt="$(jq -r --argjson id "$eval_id" \
  '.evals[] | select(.id == $id) | .prompt // empty' "$EVALS")"
if [[ -z "$fixture_rel" || -z "$prompt" ]]; then
  echo "unknown eval id: $eval_id (valid: $(valid_ids))" >&2
  exit 2
fi

target="${2:-$(mktemp -d "${TMPDIR:-/tmp}/git_checkout_eval.XXXXXX")}"
mkdir -p "$target"
target="$(cd "$target" && pwd -P)"

# Every fixture stager clears and rebuilds the target it is handed.
bash "$HARNESS/$fixture_rel" "$target" >/dev/null

sandbox_repo="$target/repo"
snap="$target/.eval"
mkdir -p "$snap"
git -C "$sandbox_repo" symbolic-ref --quiet --short HEAD > "$snap/branch_before"
git -C "$sandbox_repo" rev-parse HEAD > "$snap/head_before"
git -C "$sandbox_repo" for-each-ref --format='%(refname:short) %(objectname)' \
  refs/heads > "$snap/branches_before"
git -C "$sandbox_repo" status --porcelain=v1 --untracked-files=all \
  > "$snap/status_before"
: > "$snap/remote_heads"
for bare in "$target"/*.git; do
  [[ -d "$bare" ]] || continue
  remote="$(basename "$bare" .git)"
  git --git-dir="$bare" for-each-ref \
    --format="$remote %(refname:short) %(objectname)" refs/heads \
    >> "$snap/remote_heads"
done

printf 'sandbox_repo=%s\n' "$(printf %q "$sandbox_repo")"
printf 'skill_path=%s\n'   "$(printf %q "$SKILL_MD")"
printf 'prompt=%s\n'       "$(printf %q "$prompt")"
