#!/usr/bin/env bash
# grade.sh — deterministic grader for the executive_summary behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj> [response_file]
#
# Checks the delivered summary.md against the skill's output contract:
#   1. the summary exists and is non-empty continuous prose with no bullet or
#      numbered list markers;
#   2. the word count is 8% to 17% of the source's word count (the 10-15%
#      target with measurement tolerance);
#   3. the summary ends with a 1-to-10 self-rating;
#   4. no term from forbidden.txt (facts the source does not carry) appears.
#
# Prints one PASS/FAIL line per check and exits 1 when any check fails.

set -uo pipefail

eval_id="${1:?eval id required}"
proj="${2:?sandbox project required}"
response="${3:-}"

[[ -n "$eval_id" ]] || { printf 'eval id required\n' >&2; exit 2; }

summary="$proj/summary.md"
source="$proj/source.md"
forbidden="$proj/forbidden.txt"

fail=0
check() {
  local label="$1"; shift
  if "$@"; then
    printf '  PASS  %s\n' "$label"
  else
    printf '  FAIL  %s\n' "$label"
    fail=1
  fi
}

check "summary.md exists and is non-empty" test -s "$summary"
check "source.md exists and is non-empty" test -s "$source"

if [[ -s "$summary" && -s "$source" ]]; then
  # No bullet or numbered list markers at the start of a line. The scan reads
  # the file as UTF-8 in Python so a multibyte bullet never depends on the
  # inherited locale the way a POSIX bracket expression does.
  markers="$(python3 - "$summary" <<'PY'
import re, sys
pattern = re.compile(r"^\s*(?:\(?\d+[.)]|[-*+\u2022\u00b7\u2023\u25aa])\s+")
bad = []
for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    if pattern.match(line):
        bad.append(f"{n}:{line.rstrip()}")
print("\n".join(bad))
PY
)"
  if [[ -n "$markers" ]]; then
    printf '  FAIL  no bullet or numbered list markers\n'
    printf '%s\n' "$markers" | head -5 | sed 's/^/        /'
    fail=1
  else
    printf '  PASS  no bullet or numbered list markers\n'
  fi

  ratio_result="$(python3 - "$source" "$summary" <<'PY'
import re, sys
source_words = len(open(sys.argv[1], encoding="utf-8").read().split())
delivered_words = len(open(sys.argv[2], encoding="utf-8").read().split())
ratio = delivered_words / source_words if source_words else 0.0
ok = 0.08 <= ratio <= 0.17
print(f"{delivered_words} {source_words} {ratio:.3f} {'ok' if ok else 'bad'}")
PY
)"
  read -r dwords swords ratio verdict <<<"$ratio_result"
  check "word count $dwords is 8-17% of $swords (${ratio})" test "$verdict" = ok

  rating_result="$(python3 - "$summary" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read().strip()
tail = text[-400:]
ok = bool(re.search(r"(?<![0-9])(?:[1-9]|10)\s*/\s*10", tail)
          or re.search(r"(?i)\brating\b[^0-9]{0,20}(?:[1-9]|10)\b", tail))
print("ok" if ok else "bad")
PY
)"
  check "ends with a 1-to-10 self-rating" test "$rating_result" = ok

  forbidden_hit=0
  if [[ -f "$forbidden" ]]; then
    while IFS= read -r term; do
      [[ -n "$term" ]] || continue
      if grep -Fqi -- "$term" "$summary"; then
        printf '  FAIL  invented term absent: %s\n' "$term"
        forbidden_hit=1
      fi
    done < "$forbidden"
  fi
  if [[ "$forbidden_hit" -eq 0 ]]; then
    printf '  PASS  no forbidden invented term\n'
  else
    fail=1
  fi
else
  printf '  FAIL  summary and source readable\n'
  fail=1
fi

if [[ -n "$response" && -s "$response" ]]; then
  printf '  PASS  response captured\n'
else
  printf '  FAIL  response captured\n'
  fail=1
fi

exit "$fail"
