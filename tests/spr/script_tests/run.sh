#!/usr/bin/env bash
# script_tests/run.sh — prove grade.sh's PASS and FAIL directions.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GRADE="$(cd "$HERE/.." && pwd)/evals/grade.sh"
SCRATCH="$(mktemp -d "${TMPDIR:-/tmp}/spr_grade_cases.XXXXXX")"
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

case_dir() {
  local dir="$SCRATCH/$1"
  mkdir -p "$dir"
  printf 'First paragraph of the source.\n\nSecond paragraph of the source.\n' > "$dir/source.md"
  printf 'spaced repetition software\n' > "$dir/forbidden.txt"
  printf 'worker completed\n' > "$dir/response.txt"
  printf '%s\n' "$dir"
}

# PASS: two bullets cover two paragraphs, no punctuation, rating present.
d="$(case_dir good)"
printf -- '- first paragraph concept\n- second paragraph concept\n8\n' > "$d/spr.md"
check "PASS: a compliant SPR passes" bash -c "\"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: fewer bullets than paragraphs.
d="$(case_dir coverage)"
printf -- '- only one concept\n8\n' > "$d/spr.md"
check "FAIL: too few bullets fails coverage" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: numbered list.
d="$(case_dir numbered)"
printf -- '- first paragraph concept\n1. second paragraph concept\n8\n' > "$d/spr.md"
check "FAIL: a numbered list fails the list check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: trailing punctuation on a bullet.
d="$(case_dir punctuation)"
printf -- '- first paragraph concept.\n- second paragraph concept\n8\n' > "$d/spr.md"
check "FAIL: trailing punctuation fails the bullet check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: out-of-scope term.
d="$(case_dir forbidden)"
printf -- '- first paragraph concept\n- second paragraph concept\n- spaced repetition software\n8\n' > "$d/spr.md"
check "FAIL: an out-of-scope term fails the scope check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

# FAIL: missing rating.
d="$(case_dir norating)"
printf -- '- first paragraph concept\n- second paragraph concept\n' > "$d/spr.md"
check "FAIL: a missing rating fails the rating check" bash -c "! \"$GRADE\" x \"$d\" \"$d/response.txt\" >/dev/null"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ "$fail" -eq 0 ]]
