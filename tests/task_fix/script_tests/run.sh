#!/usr/bin/env bash
# Grader-level checks for tests/task_fix/evals/grade.sh. Each case stages a
# fixture with evals/stage.sh outside the checkout, grades it against a chosen
# response, and reads one check's PASS or FAIL line from the grader's output.
#
# These cases back grader edits with evidence in the tree, as TESTING.md asks:
# a tightened check carries a case the old check passed although the property
# failed, next to controls showing the check still separates a good report
# from a bad one. One more check covers the eval runner's stop on a failed or
# empty stage.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EVALS="$HERE/../evals"

pass=0
fail=0
check() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    pass=$((pass + 1))
    printf '  PASS  %s\n' "$label"
  else
    fail=$((fail + 1))
    printf '  FAIL  %s\n' "$label"
  fi
}

ROOT="$(mktemp -d "${TMPDIR:-/tmp}/task_fix_script_tests.XXXXXX")"
trap 'rm -rf "$ROOT"' EXIT

# grader_says <eval_id> <response_file> <check label> <PASS|FAIL> -> the grader,
# run on a freshly staged fixture with RESPONSE_FILE set to the response file,
# prints that verdict for that check.
grader_says() {
  local eval_id=$1 response=$2 label=$3 want=$4 target got
  target="$(mktemp -d "$ROOT/$eval_id.XXXXXX")"
  bash "$EVALS/stage.sh" "$eval_id" "$target" >/dev/null || return 1
  got="$(RESPONSE_FILE="$response" bash "$EVALS/grade.sh" "$eval_id" "$target/proj" 2>&1 \
    | awk -v l="$label" '$0 == "  PASS  " l { print "PASS" } $0 == "  FAIL  " l { print "FAIL" }')"
  [[ "$got" == "$want" ]]
}

# --- the archived-count absence check fails when no report is readable -------

# The check this replaced, `! disposition_blocks | grep -qiE ...`, passed on a
# missing response, because the `!` turned the failed pipeline into success. An
# absence check must fail like every other report check when there is no
# report to read.
NO_COUNT="the report carries no archived-count line"
LIVE_LINE='repeated-link: tasks/api_export-gzip.md -> tasks/api_export-schema.md, linked from ## Goal and ## Context, regrouped'
COUNT_LINE='repeated-link: 1 findings on archived tasks, reported with their bodies left as archived'

printf '%s\n' "$LIVE_LINE" > "$ROOT/live_only.txt"
printf '%s\n%s\n' "$LIVE_LINE" "$COUNT_LINE" > "$ROOT/with_count.txt"

check "a missing response fails the archived-count absence check" \
  grader_says regroup_live_skip_archived "$ROOT/missing.txt" "$NO_COUNT" FAIL
check "a report without the count line passes the absence check" \
  grader_says regroup_live_skip_archived "$ROOT/live_only.txt" "$NO_COUNT" PASS
check "a report with the count line fails the absence check" \
  grader_says regroup_live_skip_archived "$ROOT/with_count.txt" "$NO_COUNT" FAIL

# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox project, before any worker could start.
check "the eval runner's stage() raises on a failed or empty stage" \
  python3 "$HERE/../../lib/check_stage_guard.py" "$EVALS"

printf 'task_fix script_tests: %s pass, %s fail\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
