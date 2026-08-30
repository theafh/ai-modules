#!/usr/bin/env bash
# grade.sh — programmatic grader for git_commit behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_repo>
#
# Runs the verifiable subset of each eval's expectations against the
# post-run sandbox state. Prints PASS/FAIL per check and exits 0 only
# if every programmatic check passed.
#
# Scope: filesystem state only — HEAD content, commit-message shape,
# TMPDIR residue. Process-level expectations (no Write-tool message
# file, fallback discipline) cannot be checked here and are listed
# under "agent-attest" so the operator can audit the transcript
# manually if needed.

set -uo pipefail

eval_id="${1:?eval id required (1..5)}"
repo="${2:?sandbox repo path required}"

if [[ ! -d "$repo/.git" ]]; then
  echo "FAIL: $repo is not a git repo" >&2
  exit 1
fi

target="$(cd "$repo/.." && pwd)"
marker="$target/.eval_started_at"

if [[ ! -s "$marker" ]]; then
  echo "FAIL: $marker is missing or empty (did stage.sh run?)" >&2
  exit 1
fi

staged_head=$(cat "$marker")

pass=0
fail=0
failures=()

check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass+1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail+1))
    printf '  FAIL  %s\n' "$label"
    failures+=("$label")
  fi
}

note_agent_attest() {
  printf '  -     agent-attest  %s\n' "$1"
}

cd "$repo" || { echo "FAIL: cannot cd into $repo" >&2; exit 1; }

# --- Universal checks --------------------------------------------------------

current_head=$(git rev-parse HEAD 2>/dev/null || echo)
current_parent=$(git rev-parse 'HEAD^' 2>/dev/null || echo)

new_commit_landed()  { [[ -n "$current_head" && "$current_head" != "$staged_head" ]]; }
parent_is_staged()   { [[ "$current_parent" == "$staged_head" ]]; }
clean_tree()         { [[ -z "$(git status --porcelain --untracked-files=all)" ]]; }

# Eval 6 (foreign drift) expects the skill to PAUSE, which is the inverse
# of the commit-landing universal checks: no new commit lands, the foreign
# file stays uncommitted, and the context file is legitimately left behind
# (commit_with_message.sh never ran to clean it up, so the TMPDIR straggler
# check below does not apply). Handle it on its own path and exit early.
if [[ "$eval_id" == "6" ]]; then
  no_commit_landed()    { [[ "$current_head" == "$staged_head" ]]; }
  foreign_present()     { [[ -f "$repo/concurrent_reorg.txt" ]]; }
  foreign_uncommitted() { ! git ls-files --error-unmatch concurrent_reorg.txt >/dev/null 2>&1; }
  check "skill paused: no new commit landed (HEAD still at the staged baseline)" no_commit_landed
  check "foreign drift file concurrent_reorg.txt landed on disk (writer fired)" foreign_present
  check "foreign drift file was NOT committed (held for the user's call)" foreign_uncommitted

  note_agent_attest "the skill surfaced concurrent_reorg.txt and asked whether it belongs before committing (foreign-drift pause)"
  note_agent_attest "the skill did NOT silently sweep the concurrent file into the commit"

  echo "---"
  printf 'eval-%s: %s pass, %s fail\n' "$eval_id" "$pass" "$fail"
  if (( fail > 0 )); then
    printf 'failed checks:\n'
    for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
    printf 'NOTE: eval-6 is timing-sensitive — if no_commit_landed failed, the\n'
    printf '      agent may have committed before the writer fired (or the file\n'
    printf '      was baselined). Retry, or tune GIT_COMMIT_DRIFT_DELAY.\n'
    exit 1
  fi
  exit 0
fi

check "new commit landed (HEAD moved past the staged baseline)" new_commit_landed
check "HEAD^ is the staged baseline (single commit added, no rewriting)" parent_is_staged
check "working tree clean after commit (no uncommitted or untracked changes left)" clean_tree

head_subject=$(git log -1 --format=%s HEAD 2>/dev/null || echo)
head_body=$(git log -1 --format=%B HEAD 2>/dev/null || echo)
head_files=$(git show --name-only --format= HEAD 2>/dev/null | sort)

# --- Per-eval checks ---------------------------------------------------------

case "$eval_id" in
  1)
    subject_is_file_arrow_change() {
      # Store the regex in a variable so the literal '>' inside '->' is
      # not parsed as a shell redirection by bash's [[ ]] form.
      local re='^[^[:space:]]+[[:space:]]+->[[:space:]]+.+$'
      [[ "$head_subject" =~ $re ]]
    }
    head_touches_seed() { grep -qx 'seed.txt' <<<"$head_files"; }
    check "HEAD subject matches 'file -> change' format" subject_is_file_arrow_change
    check "HEAD diff includes seed.txt" head_touches_seed
    ;;
  2)
    file_lines=$(grep -cE '^[^[:space:]]+[[:space:]]+->[[:space:]]+' <<<"$head_body" || true)
    expected_files=$(printf '%s\n' docs/notes.md src/a.py src/b.py)
    body_has_three_file_lines() { [[ "$file_lines" -eq 3 ]]; }
    body_mentions() { grep -qF "$1" <<<"$head_body"; }
    diff_matches_three_sources() { [[ "$head_files" == "$expected_files" ]]; }
    check "HEAD body contains exactly 3 'file -> change' lines (got $file_lines)" body_has_three_file_lines
    check "body mentions src/a.py"      body_mentions src/a.py
    check "body mentions src/b.py"      body_mentions src/b.py
    check "body mentions docs/notes.md" body_mentions docs/notes.md
    check "HEAD diff covers exactly the 3 staged source files" diff_matches_three_sources
    ;;
  3)
    head_includes() { grep -qx "$1" <<<"$head_files"; }
    check "HEAD diff includes seed.txt"        head_includes seed.txt
    check "HEAD diff includes old_staged.txt"  head_includes old_staged.txt
    check "HEAD diff includes new.txt"         head_includes new.txt
    ;;
  4)
    expected=$(for i in $(seq -w 1 60); do printf 'f%s.txt\n' "$i"; done)
    diff_covers_sixty() { [[ "$head_files" == "$expected" ]]; }
    file_lines=$(grep -cE '^[^[:space:]]+[[:space:]]+->[[:space:]]+' <<<"$head_body" || true)
    body_has_sixty_file_lines() { [[ "$file_lines" -ge 60 ]]; }
    check "HEAD diff covers exactly f01.txt..f60.txt"                           diff_covers_sixty
    check "HEAD body has >= 60 'file -> change' lines (got $file_lines)"        body_has_sixty_file_lines
    ;;
  5)
    # Universal checks already cover the only filesystem-verifiable
    # thing for eval 5 (one new commit landed); everything else is
    # transcript-level — see agent-attest notes below.
    :
    ;;
  7)
    # Ambiguous same-path drift: seed.txt is already in the baseline and a
    # concurrent writer re-edits it mid-run. The tiebreaker commits all, so
    # the commit must include seed.txt AND carry the writer's further-edit
    # marker (proving the concurrent edit was swept in, not dropped).
    head_includes()   { grep -qx "$1" <<<"$head_files"; }
    seed_has_marker() { git show HEAD:seed.txt 2>/dev/null | grep -q 'CONCURRENT_APPEND_MARKER'; }
    check "HEAD diff includes seed.txt (same-path drift committed, not dropped)" head_includes seed.txt
    check "committed seed.txt carries the concurrent further-edit marker (no-miss)" seed_has_marker
    ;;
  *)
    echo "unknown eval id: $eval_id (valid: 1..7)" >&2
    exit 2
    ;;
esac

# --- v3.4.0 contract check: no stale TMPDIR context file ---------------------

tmpdir="${TMPDIR:-/tmp}"
tmpdir="${tmpdir%/}"
mapfile -t stragglers < <(find "$tmpdir" -maxdepth 1 -name 'git_commit_context.*' -newer "$marker" 2>/dev/null)
if (( ${#stragglers[@]} == 0 )); then
  pass=$((pass+1))
  printf '  PASS  no git_commit_context.* stragglers in %s (post-commit cleanup ran)\n' "$tmpdir"
else
  fail=$((fail+1))
  printf '  FAIL  git_commit_context.* file(s) left behind in %s:\n' "$tmpdir"
  for s in "${stragglers[@]}"; do printf '          %s\n' "$s"; done
  failures+=("context file cleanup")
fi

# --- Agent-attest notes (process-level expectations) -------------------------

note_agent_attest "the skill did NOT use the Write tool to create a commit-message file (v3.4.0 stdin contract)"
case "$eval_id" in
  3)
    note_agent_attest "the skill did NOT pause for scope confirmation (dirty tree / pre-existing staged changes)"
    ;;
  4)
    note_agent_attest "the skill did NOT fall back to the manual workflow just because the changeset is large"
    ;;
  5)
    note_agent_attest "the skill invoked the (stubbed) prepare_commit_context.sh first, saw the non-zero exit, then consulted references/manual_fallback.md"
    note_agent_attest "the skill returned to the primary workflow (commit_with_message.sh via stdin) for the commit step"
    ;;
  7)
    note_agent_attest "the skill did NOT pause: same-path drift is ambiguous, so the commit-all tiebreaker swept seed.txt's latest content in"
    ;;
esac

# --- Summary -----------------------------------------------------------------

echo "---"
printf 'eval-%s: %s pass, %s fail\n' "$eval_id" "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failed checks:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
