#!/usr/bin/env bash
# script_tests/run.sh — static contract checks for guardrail_audit.
#
# Covers the acceptance items that are filesystem / SKILL.md reads:
# frontmatter, authority wiring, audit bound, no restated hub content,
# hub forward-references left intact, registration surfaces.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/ai_dev/skills/guardrail_audit/SKILL.md"
HUB="$REPO_ROOT/plugins/ai_dev/skills/guardrail/SKILL.md"
ARCH_REF="$REPO_ROOT/plugins/ai_dev/skills/guardrail/references/architecture.md"

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

# section_has <file> <tag> <pattern> — match inside one pseudo-XML block, so a
# pin proves the rule landed in the section that owns it.
section_has() {
  awk -v tag="$2" '
    index($0, "<" tag ">") { inside = 1 }
    inside                 { print }
    index($0, "</" tag ">") { inside = 0 }
  ' "$1" | grep -Eq "$3"
}

printf 'guardrail_audit script_tests\n'

check "SKILL.md exists" test -f "$SKILL"
check "frontmatter name: guardrail_audit" file_has "$SKILL" '^name: guardrail_audit$'
check "frontmatter version: 1.0.4" file_has "$SKILL" '^version: 1\.0\.4$'
check "dual-audience description mentions read-only audit" \
  file_has "$SKILL" '^description:.*[Rr]ead-only audit'
check "description distinct from hub explain/suggest/create surface" \
  file_has "$SKILL" 'route to the guardrail hub'

check "body opens with <authority> naming the guardrail hub" \
  bash -c "awk '/<authority>/,/<\/authority>/' \"$SKILL\" | grep -Eq 'guardrail.*hub|hub skill'"
check "authority appears before workflow" \
  bash -c "grep -n '<authority>\\|<workflow>' \"$SKILL\" | head -2 | tr '\\n' ' ' | grep -Eq 'authority.*workflow'"

check "explicit high-confidence / non-exhaustive audit bound" \
  file_has "$SKILL" '<audit_bound>'
check "audit bound limits to high-confidence cases" \
  file_has "$SKILL" 'high-confidence'
check "audit bound states exhaustive coverage excluded" \
  file_has "$SKILL" 'Exhaustive coverage'

check "normative reading block present" file_has "$SKILL" '<normative_reading>'
check "normative reading treats mixed guarding sentences as guarding" \
  file_has "$SKILL" 'mixed sentence that both guards and describes'
check "normative reading reports unmet work with code as side to move" \
  file_has "$SKILL" 'unmet work'
check "finding_classes block present" file_has "$SKILL" '<finding_classes>'
check "stale-prone guarding-statement finding class named" \
  file_has "$SKILL" 'stale-prone content'
check "unused-technology descriptive finding class named" \
  file_has "$SKILL" 'naming a technology, component, or convention the code does not use'
check "unused-technology class excludes unmet rules" \
  file_has "$SKILL" 'rule the code has not reached draws no such finding'
check "empty-or-harness-locked tier-3 finding class named" \
  file_has "$SKILL" 'empty or harness-locked tier-3'
check "doc-vs-code scopes both-directions to descriptive statements" \
  file_has "$SKILL" 'purely descriptive statement'
check "output_contract closing question omits softening for guarding findings" \
  file_has "$SKILL" 'Never offer softening the rule'

# Declared-direction register: an unreached ## Direction target is drive-toward
# work, cited from the hub rather than restated here.
check "normative reading carries the declared-direction register" \
  section_has "$SKILL" normative_reading 'declared-direction register'
check "normative reading names drive-toward work for an unreached target" \
  section_has "$SKILL" normative_reading 'drive-toward work'
check "unused-technology class carves out an unreached Direction target" \
  section_has "$SKILL" finding_classes 'neither does a .## Direction. target the code has not reached'
check "doc-vs-code step reports an unreached target as drive-toward work" \
  section_has "$SKILL" workflow 'declared direction target the code has not reached, report drive-toward work'
check "finding_shape names the third reconcile shape for a direction target" \
  section_has "$SKILL" finding_shape 'declared direction target the code has not reached'
check "finding_shape scopes both-directions to present-tense description" \
  section_has "$SKILL" finding_shape 'present-tense description'
check "output_contract closing question omits softening for direction findings" \
  section_has "$SKILL" output_contract 'Never offer softening the target to the code'
check "direction passages cite the hub instead of restating it" \
  file_has "$SKILL" 'declared-direction register the hub defines'

# No restated hub definitional content beyond citation.
check "no restated Tier 1/2/3 numbered hierarchy list" \
  file_lacks "$SKILL" 'Tier 1 — identity|Tier 2 — domain|Tier 3 — operating'
check "no restated CHARTER/ARCHITECTURE/TESTING/SECURITY inventory list as owned definition" \
  bash -c "! grep -E 'Four core guardrail types are recognized' \"$SKILL\""
check "no restated presence-gating recipe beyond citation" \
  bash -c "! grep -E 'test -f \"\\\$?\{?root' \"$SKILL\""

# Hub forward-references left intact (canonical hub forward).
check "hub description still routes to guardrail_audit" \
  file_has "$HUB" 'route to guardrail_audit'
check "hub when_to_activate still routes audit requests" \
  bash -c "awk '/<when_to_activate>/,/<\/when_to_activate>/' \"$HUB\" | grep -Eq 'guardrail_audit'"
check "hub family still lists guardrail_audit" \
  bash -c "awk '/<family>/,/<\/family>/' \"$HUB\" | grep -Eq 'guardrail_audit'"
check "hub role states rules hold whether or not code satisfies them" \
  file_has "$HUB" 'whether or not the code satisfies it yet'
check "hub role names touch-it-and-fix-it" \
  file_has "$HUB" 'touch-it-and-fix-it'
check "hub drops auto-load claim" \
  file_lacks "$HUB" 'the harness loads them automatically'
check "hub carries bring touched code to the rule behaviour" \
  file_has "$HUB" 'Bring touched code to the rule'
check "hub carries write-side placement rule" \
  file_has "$HUB" 'placement rule \(write-side\)'

check "hub hierarchy names the declared-direction register" \
  section_has "$HUB" hierarchy '\*\*Declared direction\.\*\*'
check "hub hierarchy keeps Verified rule beside it" \
  section_has "$HUB" hierarchy '\*\*Verified rule\.\*\*'
check "hub hierarchy keeps Descriptive context beside it" \
  section_has "$HUB" hierarchy '\*\*Descriptive context\.\*\*'
check "hub declared-direction target holds whether or not the code reached it" \
  section_has "$HUB" hierarchy 'holds as a standing commitment whether or not the code has reached it'
check "hub descriptive register scopes truthfulness to present-tense description" \
  section_has "$HUB" hierarchy 'applies to present-tense description'
check "hub format_contract names the third register in its lead-in" \
  section_has "$HUB" format_contract 'a target where it declares direction'
check "hub format_contract forbids a per-item shipped-or-remaining ledger" \
  section_has "$HUB" format_contract 'no per-item shipped-or-remaining ledger'
check "hub carries the steer-toward-direction guard behaviour" \
  section_has "$HUB" consumption 'Steer work toward the declared direction'
check "hub counts five guard behaviours" \
  file_has "$HUB" 'Five guard behaviours hold at every touchpoint'
check "hub drops the four-behaviour count" \
  file_lacks "$HUB" 'Four guard behaviours hold at every touchpoint'
check "hub surface-never-auto-resolve reports drive-toward work on a target" \
  section_has "$HUB" consumption 'report drive-toward work'
check "hub scopes both reconcile directions to a present-tense conflict" \
  file_lacks "$HUB" 'Keep both reconcile directions only for descriptive conflicts'

# ARCHITECTURE.md reference: the section states the target, never a ledger.
check "architecture reference intro names the declared-direction register" \
  bash -c "head -4 \"$ARCH_REF\" | grep -Eq 'declared direction'"
check "architecture reference intro drops the descriptive-end framing" \
  file_lacks "$ARCH_REF" 'descriptive end of the enforcement spectrum'
check "architecture reference tells built from intended at the section boundary" \
  file_has "$ARCH_REF" 'told apart at the section boundary'
check "architecture reference names per-item build-status narration as drift" \
  file_has "$ARCH_REF" 'Per-item build-status narration inside .## Direction. is the drift'
check "architecture reference refreshes Direction only when the target changes" \
  file_has "$ARCH_REF" 'refreshed when the target changes'
check "architecture reference drops the landed-direction bookkeeping" \
  file_lacks "$ARCH_REF" 'landed direction moves from intended to built'
check "architecture reference template note carries the target, not its state" \
  file_has "$ARCH_REF" 'The section carries the target, never its completion'

# Registration surfaces.
check "listed in plugins/ai_dev/README.md" \
  file_has "$REPO_ROOT/plugins/ai_dev/README.md" 'guardrail_audit'
check "listed in root README.md" \
  file_has "$REPO_ROOT/README.md" 'guardrail_audit'
check "marketplace .agents mentions guardrail_audit sibling" \
  file_has "$REPO_ROOT/.agents/plugins/marketplace.json" 'guardrail_audit sibling'
check "marketplace .claude-plugin mentions guardrail_audit sibling" \
  file_has "$REPO_ROOT/.claude-plugin/marketplace.json" 'guardrail_audit sibling'

# Plugin meta lockstep, asserted against whatever .claude-plugin/plugin.json
# currently says. See tests/lib/plugin_version.sh for the rule it encodes.
check_plugin_version_lockstep ai_dev

# Skill directory layout.
check "skill directory has only SKILL.md (slim sibling, no copied references/)" \
  bash -c '[[ "$(ls -1 "'"$REPO_ROOT"'/plugins/ai_dev/skills/guardrail_audit" | wc -l | tr -d " ")" == "1" ]] && test -f "'"$SKILL"'"'

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi

# Sandbox git must never be able to commit into the host checkout.
bash "$HERE/sandbox_git_isolation.sh"
