#!/usr/bin/env bash
# grade.sh — deterministic grader for guardrail_audit behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_proj> [response.txt]
#
# Always checks byte-identity of the staged tree. When response.txt is
# supplied, also checks the programmatic substring markers for that eval.
# Agent-attest expectations that need qualitative reading stay noted.

set -uo pipefail

eval_id="${1:?eval id required}"
proj="${2:?sandbox proj path required}"
response="${3:-}"

if [[ ! -d "$proj" ]]; then
  echo "FAIL: $proj is not a directory" >&2
  exit 1
fi

target="$(cd "$proj/.." && pwd)"
hash_file="$target/.tree_sha256"
if [[ ! -s "$hash_file" ]]; then
  echo "FAIL: $hash_file missing (did setup.sh run?)" >&2
  exit 1
fi

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

note_agent_attest() { printf '  -     agent-attest  %s\n' "$1"; }

tree_unchanged() {
  local tmp
  tmp="$(mktemp)"
  (
    cd "$proj" || exit 1
    # Match record_tree_hashes: exclude .git so hook/template noise never
    # counts as a skill edit.
    if command -v sha256sum >/dev/null 2>&1; then
      find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 sha256sum
    else
      find . -type f ! -path './.git/*' -print0 | sort -z | xargs -0 shasum -a 256
    fi
  ) > "$tmp"
  cmp -s "$hash_file" "$tmp"
  local rc=$?
  rm -f "$tmp"
  return "$rc"
}

file_absent() { [[ ! -e "$proj/$1" ]]; }

response_has() {
  [[ -n "$response" && -f "$response" ]] || return 1
  grep -Eiq "$1" "$response"
}

# The skill's <output_contract> closing question. Its wording is free-form
# prose — the most variable surface there is — so accept the whole vocabulary
# the contract sanctions instead of pinning one phrasing. Every branch shares
# this one definition so a contract change moves them together.
ASKS_PROCEED='how to proceed|how would you like to proceed|want to proceed|would you like|which .+ reconcile|want me to|should i draft|evolve the code|park the finding'

# The normative doc-vs-code outcome: the code, not the rule, is the side that
# moves. The contract sanctions several phrasings — "name the code as the side
# to move", "the code is the side that must move", "evolve the code toward the
# rule" — so accept that family instead of pinning one preposition.
CODE_IS_SIDE_TO_MOVE='unmet work|code (as|is) the side|the code .{0,40}(must move|to move|catch up)|evolve the code|code toward'

# The normative declared-direction outcome: an unreached `## Direction` target
# is drive-toward work. The contract sanctions several phrasings — "drive-toward
# work", "move the code toward the target", "revise the target deliberately" —
# so accept that family instead of pinning one.
DRIVES_TOWARD='drive-toward|drives? toward|driving toward|(move|moving|moves) the code toward|revise the target|toward the target'

# A response legitimately *names* a move in order to say it does not apply
# ("offers no softening of the target"). Drop negated lines before deciding, so
# only a surviving line counts as the move the audit actually made. Same shape
# as raises_no_missing_doc_error below, generalised over a pattern.
NEGATED='(^|[^a-z])(no|not|never|nor|neither)([^a-z]|$)|without|rather than|instead of|refus|declin|avoid|n'"'"'t|do(es)? not|cannot|out of scope|not a reconcile'

# The `## Direction` target's own vocabulary. A `bring the doc back to the code`
# reconcile option only argues against the target when the same finding block
# names that target; the same phrase offered for an unrelated finding (a
# header-casing doc-vs-code choice, say) says nothing about the target and must
# not count. Bare `direction` is the ordinary English word rather than the
# target's name, so only the target-specific tokens scope the bring-back branch.
TARGET_SUBJECT='target|## Direction|StreamPipeline|streaming pipeline|pipeline\.py'

# Softening or deletion of the target, or moving the target's own doc back to
# the code. POSIX `grep -E` has no lookahead, so the subject requirement sits on
# the bring-back alternative itself and both orders are spelled out. The
# soften alternative stays whole and unqualified — "soften the doc" still counts
# because the fixture's `## Direction` lives in ARCHITECTURE.md — and the delete
# alternative accepts a `##`-prefixed heading, backticked or not, so "delete the
# ## Direction section" and "delete the `## Direction` section" both count.
SOFTENS_OR_DELETES_TARGET="soften(ing)? the (target|direction|statement|doc)|(bring the (doc|ARCHITECTURE\.md) back to the (code|repositor).*($TARGET_SUBJECT)|($TARGET_SUBJECT).*bring the (doc|ARCHITECTURE\.md) back to the (code|repositor))|(delete|deleting|remove|removing|drop|dropping) the (unbuilt |unreached )?(\`)?(## )?(target|Direction( section)?)(\`)?"

# The bring-back offer without its subject requirement: the block supplies the
# subject token, so the offer may sit in a sentence of its own.
BRINGS_BACK='bring the (doc|ARCHITECTURE\.md) back to the (code|repositor)'

# One sentence per line, hard wraps collapsed. A wrap falling mid-phrase makes
# a line-based match miss text that is present, and a negation sitting on the
# line above the claim it negates would be invisible to line-based stripping.
# The sentence is the unit a negation actually governs.
sentences() {
  tr '\n' ' ' < "$response" | sed -E 's/[[:space:]]+/ /g; s/([.!?]) /\1\n/g'
}

# Multi-word marker present anywhere in the response, wraps collapsed.
response_has_flat() {
  [[ -n "$response" && -f "$response" ]] || return 1
  sentences | grep -Eiq "$1"
}

mentions_unnegated() {
  [[ -n "$response" && -f "$response" ]] || return 1
  sentences | grep -Ei "$1" | grep -Eiqv "$NEGATED"
}

lacks_unnegated() { ! mentions_unnegated "$1"; }

# One block per line: a paragraph's sentences stay together, and each list item
# starts its own block. A markdown heading is carried into the block it
# introduces, so a blank line under the heading does not detach its text from
# the finding it names. A bring-back offer is often a sentence of its own, with
# the target named in the sentence before it inside the same finding block,
# while a neighbouring bullet about an unrelated finding must stay out of scope.
# The heading is also closed with a sentence terminator, so the block's later
# split on sentence-final punctuation keeps the heading a sentence of its own:
# its text still supplies the subject token, while a negation inside it cannot
# reach the paragraph's first sentence and silence the offer there.
blocks() {
  [[ -f "$response" ]] || return 1
  awk '
    function flush() {
      if (buf != "") {
        gsub(/[[:space:]]+/, " ", buf)
        sub(/^ /, "", buf)
        print buf
        buf = ""
      }
    }
    /^[[:space:]]*#{1,6}[[:space:]]/ {
      flush(); in_heading = 1
      buf = ($0 ~ /[.!?][[:space:]]*$/) ? $0 : $0 "."
      next
    }
    /^[[:space:]]*$/ { if (in_heading) next; flush(); next }
    /^[[:space:]]*([-*+]|[0-9]+[.)])[[:space:]]/ { if (!in_heading) flush(); in_heading = 0 }
    { in_heading = 0; buf = (buf == "" ? $0 : buf " " $0) }
    END { flush() }
  ' "$response"
}

# The target check judges that block unit rather than one sentence alone, so a
# target named adjacent to the bring-back offer still scopes the check. The block
# supplies only the subject token; the negation filter runs on the sentence that
# carries the softening or bring-back phrase, so a sentence that only declines
# the move does not count and a neutral sentence beside it cannot re-arm it.
mentions_target_softening() {
  [[ -n "$response" && -f "$response" ]] || return 1
  local block sentence has_subject carries
  while IFS= read -r block; do
    printf '%s\n' "$block" | grep -Eiq "$SOFTENS_OR_DELETES_TARGET" || continue
    if printf '%s\n' "$block" | grep -Eiq "$TARGET_SUBJECT"; then
      has_subject=1
    else
      has_subject=0
    fi
    while IFS= read -r sentence; do
      [[ -n "$sentence" ]] || continue
      if printf '%s\n' "$sentence" | grep -Eiq "$SOFTENS_OR_DELETES_TARGET"; then
        carries=1
      elif [[ "$has_subject" == 1 ]] \
        && printf '%s\n' "$sentence" | grep -Eiq "$BRINGS_BACK"; then
        carries=1
      else
        carries=0
      fi
      [[ "$carries" == 1 ]] || continue
      printf '%s\n' "$sentence" | grep -Eiq "$NEGATED" || return 0
    done < <(printf '%s\n' "$block" | sed -E 's/([.!?]) /\1\n/g')
  done < <(blocks)
  return 1
}

lacks_target_softening() { ! mentions_target_softening; }

# A response legitimately *names* "missing-doc error" when it reports that no
# such error applies, so drop negated mentions before deciding. Only a
# surviving line is an error the audit actually raised.
raises_no_missing_doc_error() {
  [[ -n "$response" && -f "$response" ]] || return 0
  ! grep -Ei 'missing[- ]doc error|error:.*(ARCHITECTURE|TESTING|SECURITY)' "$response" \
    | grep -Eiqv 'no missing[- ]doc error|raises? no|raise no|never raises?|not an error|no error'
}

printf 'grading %s against %s\n' "$eval_id" "$proj"

check "tree byte-identical to staged fixture" tree_unchanged

case "$eval_id" in
  presence_gate)
    check "no ARCHITECTURE.md created" file_absent ARCHITECTURE.md
    check "no TESTING.md created" file_absent TESTING.md
    check "no SECURITY.md created" file_absent SECURITY.md
    if [[ -n "$response" && -f "$response" ]]; then
      check "response inventories CHARTER.md" response_has 'CHARTER\.md'
      check "response inventories CLAUDE.md" response_has 'CLAUDE\.md'
      check "response raises no missing-doc error" raises_no_missing_doc_error
      check "response asks how to proceed" response_has "$ASKS_PROCEED"
    else
      note_agent_attest "inventories CHARTER.md + CLAUDE.md; no missing-doc error; asks how to proceed"
    fi
    ;;
  doc_vs_doc)
    if [[ -n "$response" && -f "$response" ]]; then
      check "response cites hosted SaaS / multi-tenant gateway contradiction" \
        response_has 'hosted SaaS|multi-tenant|API gateway'
      check "response names CHARTER.md authoritative" \
        response_has 'CHARTER\.md.*(authoritat|higher|tier 1)|authoritat.*CHARTER'
      check "response flags ARCHITECTURE.md to reconcile" \
        response_has 'ARCHITECTURE\.md'
      check "response asks how to proceed" response_has "$ASKS_PROCEED"
    else
      note_agent_attest "doc-vs-doc contradiction with charter authoritative + architecture to reconcile"
    fi
    ;;
  doc_vs_code)
    if [[ -n "$response" && -f "$response" ]]; then
      check "response cites analytics / hosted service divergence" \
        response_has 'analytics|hosted|SaaS|serve_hosted_analytics'
      check "response cites src/analytics_api.py or code evidence" \
        response_has 'analytics_api|serve_hosted_analytics|hosted-analytics'
      check "response reports unmet work with code as side to move" \
        response_has "$CODE_IS_SIDE_TO_MOVE"
      check "response offers no softening of the rule" \
        bash -c "! grep -Eiq 'soften(ing)? the (rule|statement|doc)|bring the doc back to the code|both reconcile' \"$response\""
      check "response asks how to proceed" response_has "$ASKS_PROCEED"
    else
      note_agent_attest "doc-vs-code divergence as unmet work; code named as side to move; no softening"
    fi
    ;;
  direction_target)
    if [[ -n "$response" && -f "$response" ]]; then
      check "response names the unreached Direction target" \
        response_has_flat 'StreamPipeline|streaming pipeline|pipeline\.py'
      check "response reads it in the declared-direction register" \
        response_has_flat 'declared direction|drive-toward|Direction section|## Direction'
      check "response reports drive-toward work" response_has_flat "$DRIVES_TOWARD"
      check "response raises no describing-falsehood finding against the target" \
        lacks_unnegated 'descriptive falsehood|describing falsehood|(describes|naming|names) a (technology|component|convention|stack)[^.]{0,40}(code|repositor)[^.]{0,20}does not (use|have)|presents intention as fact|inaccurate description|untruthful'
      check "response offers no softening or deletion of the target" \
        lacks_target_softening
      check "response asks how to proceed" response_has "$ASKS_PROCEED"
    else
      note_agent_attest "unreached Direction target as drive-toward work; no describing-falsehood finding; no target softening"
    fi
    ;;
  missing_testing)
    check "no TESTING.md created" file_absent TESTING.md
    if [[ -n "$response" && -f "$response" ]]; then
      check "response proposes TESTING.md" response_has 'TESTING\.md'
      check "response grounds proposal in pytest/tests" response_has 'pytest|tests/'
      check "response asks how to proceed" response_has "$ASKS_PROCEED|draft"
    else
      note_agent_attest "grounded TESTING.md proposal; no file created"
    fi
    ;;
  nature_mismatch)
    check "no ARCHITECTURE.md created" file_absent ARCHITECTURE.md
    check "no TESTING.md created" file_absent TESTING.md
    check "no SECURITY.md created" file_absent SECURITY.md
    check "no CHARTER.md created" file_absent CHARTER.md
    if [[ -n "$response" && -f "$response" ]]; then
      check "response names mixed / multi-project nature" \
        response_has 'multi-project|mixed|unrelated projects'
      check "response names ARCHITECTURE mismatch rather than proposing it" \
        response_has 'mismatch|bad fit|ill-fitting|not a fit|nature'
      check "response asks how to proceed" response_has "$ASKS_PROCEED"
    else
      note_agent_attest "names multi-project mismatch; proposes nothing ill-fitting"
    fi
    ;;
  *)
    echo "FAIL: unknown eval id $eval_id" >&2
    exit 2
    ;;
esac

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
