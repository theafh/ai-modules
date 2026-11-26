#!/usr/bin/env bash
# grade.sh — deterministic grader for the spr behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj> [response_file]
#
# Checks the delivered spr.md against the skill's output contract:
#   1. spr.md exists and carries at least one bullet per source paragraph;
#   2. no numbered list appears;
#   3. no bullet ends with trailing punctuation;
#   4. no term from forbidden.txt (out-of-scope content) appears;
#   5. the document ends with a single integer rating from 1 to 10.
#
# Prints one PASS/FAIL line per check and exits 1 when any check fails.

set -uo pipefail

eval_id="${1:?eval id required}"
proj="${2:?sandbox project required}"
response="${3:-}"

[[ -n "$eval_id" ]] || { printf 'eval id required\n' >&2; exit 2; }

spr="$proj/spr.md"
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

check "spr.md exists and is non-empty" test -s "$spr"
check "source.md exists and is non-empty" test -s "$source"

if [[ -s "$spr" && -s "$source" ]]; then
  coverage="$(python3 - "$source" "$spr" <<'PY'
import re, sys
src = open(sys.argv[1], encoding="utf-8").read()
spr = open(sys.argv[2], encoding="utf-8").read()
blocks = [b for b in re.split(r"\n\s*\n", src) if b.strip()]
paragraphs = [b for b in blocks if not b.lstrip().startswith("#")]
bullets = [l for l in spr.splitlines()
           if re.match(r"^\s*[-*]\s+\S", l)]
ok = len(bullets) >= len(paragraphs)
print(f"{len(bullets)} {len(paragraphs)} {'ok' if ok else 'bad'}")
PY
)"
  read -r bullets paragraphs verdict <<<"$coverage"
  check "bullet count $bullets covers $paragraphs source paragraphs" test "$verdict" = ok

  if grep -nE '^[[:space:]]*[0-9]+[.)][[:space:]]' "$spr" >/dev/null; then
    printf '  FAIL  no numbered list\n'
    grep -nE '^[[:space:]]*[0-9]+[.)][[:space:]]' "$spr" | head -3 | sed 's/^/        /'
    fail=1
  else
    printf '  PASS  no numbered list\n'
  fi

  trailing="$(python3 - "$spr" <<'PY'
import re, sys
bad = []
for n, line in enumerate(open(sys.argv[1], encoding="utf-8"), 1):
    if re.match(r"^\s*[-*]\s+\S", line) and re.search(r"[.,;:!?]\s*$", line):
        bad.append(f"{n}:{line.rstrip()}")
print("\n".join(bad))
PY
)"
  if [[ -n "$trailing" ]]; then
    printf '  FAIL  no trailing punctuation on bullets\n'
    printf '%s\n' "$trailing" | head -3 | sed 's/^/        /'
    fail=1
  else
    printf '  PASS  no trailing punctuation on bullets\n'
  fi

  forbidden_hit=0
  if [[ -f "$forbidden" ]]; then
    while IFS= read -r term; do
      [[ -n "$term" ]] || continue
      if grep -Fqi -- "$term" "$spr"; then
        printf '  FAIL  out-of-scope term absent: %s\n' "$term"
        forbidden_hit=1
      fi
    done < "$forbidden"
  fi
  if [[ "$forbidden_hit" -eq 0 ]]; then
    printf '  PASS  no out-of-scope term\n'
  else
    fail=1
  fi

  rating="$(python3 - "$spr" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read().strip()
tail = text[-200:]
ok = bool(re.search(r"(?<![0-9])(?:[1-9]|10)(?![0-9])", tail))
print("ok" if ok else "bad")
PY
)"
  check "ends with a 1-to-10 rating" test "$rating" = ok
else
  printf '  FAIL  spr and source readable\n'
  fail=1
fi

if [[ -n "$response" && -s "$response" ]]; then
  printf '  PASS  response captured\n'
else
  printf '  FAIL  response captured\n'
  fail=1
fi

exit "$fail"
