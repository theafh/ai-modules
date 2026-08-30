#!/usr/bin/env bash
# sandbox_git_isolation — prove fixture git cannot commit into the host repo.
#
# 1. Happy path: stage presence_gate; host HEAD unchanged; sandbox has its
#    own commit and its own toplevel.
# 2. Failure path: a proj without .git must make git_commit_all abort
#    rather than walking up to the host.
# 3. Failure path: a broken .git directory must also refuse.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=../evals/fixtures/_common.sh
. "$REPO_ROOT/tests/guardrail_audit/evals/fixtures/_common.sh"

pass=0
fail=0
failures=()

check() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1)); printf '  PASS  %s\n' "$label"
  else
    fail=$((fail+1)); printf '  FAIL  %s\n' "$label"; failures+=("$label")
  fi
}

printf 'guardrail_audit sandbox_git_isolation\n'

scratch="$(mktemp -d "${TMPDIR:-/tmp}/guardrail_audit_isolation.XXXXXX")"
cleanup() { rm -rf "$scratch"; }
trap cleanup EXIT

HOST_HEAD_BEFORE="$(git -C "$REPO_ROOT" rev-parse HEAD)"
git -C "$REPO_ROOT" status --porcelain > "$scratch/host_status.before"

# --- happy path: real stage ---
stage_target="$scratch/stage"
mkdir -p "$stage_target"
bash "$REPO_ROOT/tests/guardrail_audit/evals/stage.sh" presence_gate "$stage_target" \
  > "$scratch/stage.env"
# shellcheck disable=SC1091
eval "$(cat "$scratch/stage.env")"

proj_abs="$(cd "${sandbox_proj:?}" && pwd -P)"
check "stage produced sandbox_proj" test -d "$sandbox_proj"
check "sandbox is its own git toplevel" \
  test "$(git -C "$sandbox_proj" rev-parse --show-toplevel)" = "$proj_abs"
check "sandbox has a commit" \
  git -C "$sandbox_proj" rev-parse --verify HEAD
check "sandbox HEAD message is stage presence_gate" \
  test "$(git -C "$sandbox_proj" log -1 --format=%s)" = "stage presence_gate"
check "host HEAD unchanged after stage" \
  test "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$HOST_HEAD_BEFORE"
git -C "$REPO_ROOT" status --porcelain > "$scratch/host_status.after_stage"
check "host porcelain unchanged after stage" \
  cmp -s "$scratch/host_status.before" "$scratch/host_status.after_stage"
check "tree hash file present" test -s "$stage_target/.tree_sha256"

# --- failure path: no .git must refuse, not walk up ---
orphan="$scratch/orphan/proj"
mkdir -p "$orphan"
echo "orphan" > "$orphan/note.txt"
set +e
out="$(git_commit_all "$orphan" "should-not-land-on-host" 2>&1)"
rc=$?
set -e
check "git_commit_all refuses proj without .git" test "$rc" -ne 0
check "refusal mentions missing .git or refusing" \
  grep -Eq 'missing|refusing|no \.git|ensure_sandbox' <<<"$out"
check "host HEAD unchanged after refused commit" \
  test "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$HOST_HEAD_BEFORE"
git -C "$REPO_ROOT" status --porcelain > "$scratch/host_status.after_refuse"
check "host porcelain unchanged after refused commit" \
  cmp -s "$scratch/host_status.before" "$scratch/host_status.after_refuse"
check "refused commit message does not appear on host" \
  bash -c '! git -C "'"$REPO_ROOT"'" log -5 --format=%s | grep -Fx "should-not-land-on-host"'

# --- failure path: broken .git dir must not fall through to host ---
broken="$scratch/broken/proj"
mkdir -p "$broken/.git"
echo "not a real git dir" > "$broken/.git/NOT_A_REPO"
echo "x" > "$broken/file.txt"
set +e
out2="$(git_commit_all "$broken" "broken-should-not-land" 2>&1)"
rc2=$?
set -e
check "git_commit_all refuses broken .git" test "$rc2" -ne 0
check "host HEAD unchanged after broken .git attempt" \
  test "$(git -C "$REPO_ROOT" rev-parse HEAD)" = "$HOST_HEAD_BEFORE"
check "broken commit message does not appear on host" \
  bash -c '! git -C "'"$REPO_ROOT"'" log -5 --format=%s | grep -Fx "broken-should-not-land"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  printf 'last refusal output:\n%s\n' "$out"
  printf 'broken refusal output:\n%s\n' "$out2"
  exit 1
fi
exit 0
