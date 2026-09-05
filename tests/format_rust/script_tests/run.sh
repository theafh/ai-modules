#!/usr/bin/env bash
# script_tests/run.sh — static contract checks for format_rust error/panic model.
#
# Covers the acceptance items that are SKILL.md / README greps for the
# error-versus-invariant model, panic discipline, and clippy wiring.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/ai_dev/skills/format_rust/SKILL.md"
README="$REPO_ROOT/plugins/ai_dev/README.md"

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

file_has() { grep -Eq "$2" "$1"; }
file_lacks() { ! grep -Eq "$2" "$1"; }

# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"
heading_once() {
  local count
  count="$(grep -cE "^## $1\$" "$SKILL" || true)"
  [[ "$count" -eq 1 ]]
}

printf 'format_rust script_tests\n'

check "SKILL.md exists" test -f "$SKILL"
check "frontmatter name: format_rust" file_has "$SKILL" '^name: format_rust$'
check "frontmatter version: 1.3.2" file_has "$SKILL" '^version: 1\.3\.2$'

# Description: added coverage + idiom-by-consumer slot rewrite.
check "description names error-versus-invariant model" \
  file_has "$SKILL" '^description:.*error-versus-invariant'
check "description names panic discipline" \
  file_has "$SKILL" '^description:.*panic discipline'
check "description names clippy unwrap_used enforcement" \
  file_has "$SKILL" '^description:.*unwrap_used'
check "description keeps procedural flow" \
  file_has "$SKILL" '^description:.*procedural flow'
check "description keeps clippy-driven clarity" \
  file_has "$SKILL" '^description:.*clippy-driven clarity'
check "description keeps Result/Option idioms" \
  file_has "$SKILL" '^description:.*Result/Option'
check "description rewrites fallible builders slot to idiom by consumer" \
  file_has "$SKILL" '^description:.*fallible builders following the error idiom by consumer'
check "description drops project-error-types framing" \
  file_lacks "$SKILL" 'fallible builders with project error types'

# Error-versus-invariant + unwrap as assertion.
check "H2 Errors versus broken invariants once" \
  heading_once 'Errors versus broken invariants'
check "unwrap named as assertion rather than fallback" \
  file_has "$SKILL" 'assertion, not a fallback'
check "world-caused failure routes to Result" \
  file_has "$SKILL" 'failure the world causes'
check "broken guarantee routes to panic" \
  file_has "$SKILL" "program's own guarantees is false as a panic"

# Trust-boundary rule names all four construct classes.
check "H2 Panic discipline across a trust boundary once" \
  heading_once 'Panic discipline across a trust boundary'
check "trust-boundary lists all four panicking construct classes" \
  file_has "$SKILL" '`unwrap`, `expect`, direct indexing and slicing, and arithmetic that can overflow'

# expect message names the invariant.
check "H2 An expect message names the invariant once" \
  heading_once 'An expect message names the invariant'
check "expect message names invariant rather than symptom" \
  file_has "$SKILL" 'names the invariant the site rests on rather than the symptom'

# anyhow vs thiserror by consumer; severity + public response follow type.
check "H2 Error idiom follows the consumer once" \
  heading_once 'Error idiom follows the consumer'
check "anyhow for operator-read failures" \
  file_has "$SKILL" 'Use `anyhow` for a failure an operator reads'
check "thiserror for programmatic callers" \
  file_has "$SKILL" 'typed `thiserror` enum'
check "severity classification lives in the error type" \
  file_has "$SKILL" 'Put severity classification in the error type'
check "public response follows the variant" \
  file_has "$SKILL" 'public response follow the variant rather than the error'

# Downcasting signal.
check "H2 Downcasting to classify is the signal for a typed boundary once" \
  heading_once 'Downcasting to classify is the signal for a typed boundary'
check "downcasting signals typed enum" \
  file_has "$SKILL" 'downcasting a boxed error'
check "thiserror replaces hand-rolled Display and Error" \
  file_has "$SKILL" 'hand-rolled `Display` and `Error` impl pair'

# Panic ownership.
check "H2 Every panic has an owner once" \
  heading_once 'Every panic has an owner'
check "catch-panic covers only the wrapped stack" \
  file_has "$SKILL" 'covering only the stack it wraps'
check "spawned work retains join handle" \
  file_has "$SKILL" 'retain the join handle'
check "join error is logged" \
  file_has "$SKILL" 'log the resulting join error'

# Clippy wiring.
check "H2 Structural enforcement through clippy once" \
  heading_once 'Structural enforcement through clippy'
check "unwrap_used denied" \
  file_has "$SKILL" 'Deny `clippy::unwrap_used`'
check "expect_used left allowed" \
  file_has "$SKILL" 'leaving `clippy::expect_used` allowed'
check "allow-by-default restriction lints named" \
  file_has "$SKILL" 'allow-by-default restriction lints'
check "Cargo.toml lints.clippy table named" \
  file_has "$SKILL" '\[lints\.clippy\]. table in .Cargo.toml.'
check "unit-test opt-out attribute named" \
  file_has "$SKILL" '#!\[cfg_attr\(test, allow\(clippy::unwrap_used\)\)\]'
check "integration-test opt-out attribute named" \
  file_has "$SKILL" '#!\[allow\(clippy::unwrap_used\)\]'

# What denying unwrap does not buy.
check "H2 What denying unwrap does not buy once" \
  heading_once 'What denying unwrap does not buy'
check "names panic sources outside unwrap" \
  file_has "$SKILL" 'out-of-bounds indexing'
check "names dependencies still panic" \
  file_has "$SKILL" 'every dependency all still panic'
check "names unused indexing_slicing lever" \
  file_has "$SKILL" 'clippy::indexing_slicing'
check "names unused overflow-checks lever" \
  file_has "$SKILL" 'overflow-checks = true'

# Superseded passages + one canonical idiom statement.
check "no 'minimal wrapping' leftover" file_lacks "$SKILL" 'minimal wrapping'
check "no Results and Options H2" \
  bash -c "! grep -Eq '^## Results and Options\$' \"$SKILL\""
check "H2 Fallible builders once" heading_once 'Fallible builders'
check "Fallible builders defers to idiom-by-consumer" \
  file_has "$SKILL" 'Error idiom follows the consumer'
check "Fallible builders drops project-standard error type instruction" \
  file_lacks "$SKILL" 'project-standard error type'

# Family shape: plain markdown, no pseudo-XML.
check "no role/objective/policy/output_contract tags" \
  bash -c "! grep -Eq '<(role|objective|policy|output_contract)>' \"$SKILL\""

# Remaining family H2s still present once.
check "H2 Preferred style once" heading_once 'Preferred style'
check "H2 Clippy‑driven improvements once" \
  heading_once 'Clippy‑driven improvements'
check "H2 Imports once" heading_once 'Imports'
check "H2 Option predicates once" heading_once 'Option predicates'
check "H2 String prefix handling once" heading_once 'String prefix handling'
check "H2 Borrowing clarity once" heading_once 'Borrowing clarity'
check "H2 Iteration style once" heading_once 'Iteration style'
check "H2 String building once" heading_once 'String building'
check "H2 Function signatures once" heading_once 'Function signatures'

# README lockstep.
check "README drops project-error-types framing" \
  file_lacks "$README" 'fallible builders with project error types'
check "README format_rust bullet carries idiom-by-consumer phrasing" \
  file_has "$README" 'fallible builders following the error idiom by consumer'
check "README format_rust bullet names error-versus-invariant model" \
  file_has "$README" 'error-versus-invariant model with panic discipline'

# Plugin meta lockstep, asserted against whatever .claude-plugin/plugin.json
# currently says. See tests/lib/plugin_version.sh for the rule it encodes.
check_plugin_version_lockstep ai_dev

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
