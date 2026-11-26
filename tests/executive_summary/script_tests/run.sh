#!/usr/bin/env bash
# script_tests/run.sh — prove grade.sh's PASS and FAIL directions.
#
# Each case stages a source document, a summary, and a forbidden-term list,
# runs grade.sh, and asserts the check under test passes or fails.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRADE="$(cd "$HERE/.." && pwd)/evals/grade.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/es_grade_cases.XXXXXX")"
trap 'rm -rf "$SCRATCH"' EXIT

pass=0
fail=0
check() {
  local label="$1"; shift
  if "$@"; then
    printf '  ok   %s\n' "$label"
    pass=$((pass + 1))
  else
    printf '  FAIL %s\n' "$label"
    fail=$((fail + 1))
  fi
}

# A 100-word source so ratios are easy to read.
source_words() {
  local dir="$1"
  python3 - "$dir/source.md" <<'PY'
import sys
words = " ".join(["word"] * 100)
open(sys.argv[1], "w", encoding="utf-8").write(words + "\n")
PY
  printf 'fourteen million\n' > "$dir/forbidden.txt"
  printf 'worker completed\n' > "$dir/response.txt"
}

case_dir() {
  local dir="$SCRATCH/$1"
  mkdir -p "$dir"
  source_words "$dir"
  printf '%s\n' "$dir"
}

# 12 of 100 words -> 12%, inside the 8-17% window, with a rating.
good_summary() {
  printf 'The source repeats one word a hundred times. Rating: 8/10.\n'
}

# PASS direction.
d="$(case_dir good)"; good_summary > "$d/summary.md"
check "PASS: a compliant summary passes" bash -c "\"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: ratio too long.
d="$(case_dir long)"
python3 - "$d/summary.md" <<'PY'
import sys
open(sys.argv[1], "w", encoding="utf-8").write(" ".join(["extra"] * 40) + " Rating: 7/10.\n")
PY
check "FAIL: an over-long summary fails the ratio check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: bullet markers.
d="$(case_dir bullets)"
{ good_summary; printf -- '- a bullet the contract forbids\n'; } > "$d/summary.md"
check "FAIL: a bullet list fails the prose check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: a Unicode bullet marker.
d="$(case_dir unicode_bullet)"
{ good_summary; printf '\xe2\x80\xa2 a bullet the contract forbids\n'; } > "$d/summary.md"
check "FAIL: a Unicode bullet fails the prose check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: invented term.
d="$(case_dir invented)"
{ good_summary; printf 'The budget was fourteen million.\n'; } > "$d/summary.md"
check "FAIL: an invented term fails the source-boundary check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: no self-rating.
d="$(case_dir norating)"
printf 'The source repeats one word a hundred times and says nothing more at all here.\n' > "$d/summary.md"
check "FAIL: a missing self-rating fails the rating check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# The shared stage guard must hold for this runner.
if python3 "$HERE/../../lib/check_stage_guard.py" "$HERE/../evals" >/dev/null 2>&1; then
  printf '  ok   stage guard holds\n'
  pass=$((pass + 1))
else
  printf '  FAIL stage guard\n'
  fail=$((fail + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
