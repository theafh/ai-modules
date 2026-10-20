#!/usr/bin/env bash
# script_tests/run.sh: static contract checks for language_humanizer.
#
# The skill ships no bundled scripts, so this surface covers the acceptance
# items a filesystem or SKILL.md read can settle: the single-file directory, the
# pseudo-XML body, the description budget and its two router splits, dash-free
# prose, the named sections and rules, and registration lockstep. The
# behavioural items live in evals/, driven by evals/run.py, and the grader's own
# unit tests live in evals/test_grade.py. One check also covers that runner's
# stop on a failed or empty stage.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_editorial/skills/language_humanizer"
SKILL="$SKILL_DIR/SKILL.md"
PLUGIN_README="$REPO_ROOT/plugins/ai_editorial/README.md"
ROOT_README="$REPO_ROOT/README.md"
LINTER="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"

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

# section_has <file> <tag> <pattern>: match inside one pseudo-XML block, so a
# pin proves the rule landed in the section that owns it.
section_has() {
  awk -v tag="$2" '
    index($0, "<" tag ">") { inside = 1 }
    inside                 { print }
    index($0, "</" tag ">") { inside = 0 }
  ' "$1" | grep -Eq "$3"
}

# description_at_most <file> <max-chars> and description_has <file> <pattern>:
# read the frontmatter description (one double-quoted line here) and test it.
description_at_most() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r'^description: "(.*)"$', fm, re.M).group(1)
sys.exit(0 if len(desc) <= int(sys.argv[2]) else 1)
PY
}

description_has() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r'^description: "(.*)"$', fm, re.M).group(1)
sys.exit(0 if re.search(sys.argv[2], desc) else 1)
PY
}

only_skill_md() { [[ "$(ls -A "$SKILL_DIR")" == "SKILL.md" ]]; }

occurrences_are() { [[ "$(grep -Eo "$2" "$1" | wc -l | tr -d ' ')" == "$3" ]]; }

# root_section_lacks <pattern>: the root README's ai_editorial section, from its
# heading to the next one, carries no match.
root_section_lacks() {
  ! awk '/^### ai_editorial/ { inside = 1; next } /^### / { inside = 0 } inside' \
    "$ROOT_README" | grep -Eq "$1"
}

# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"

printf 'language_humanizer script_tests\n'

check "SKILL.md exists" test -f "$SKILL"
check "skill directory holds only SKILL.md" only_skill_md
check "frontmatter name matches the directory" file_has "$SKILL" '^name: language_humanizer$'
check "pseudo-XML body passes lint_pseudo_xml.py" python3 "$LINTER" --quiet "$SKILL"
check "no URL in the skill" file_lacks "$SKILL" 'https?://|www\.'
check "no em dash or en dash in the skill" file_lacks "$SKILL" '—|–'

check "description fits the 1024-character skill limit" description_at_most "$SKILL" 1024
check "description states comprehension and coherence for a named reader" \
  description_has "$SKILL" 'comprehension and coherence for a named reader'
check "description routes the short-version split to executive_summary" \
  description_has "$SKILL" 'fraction of the original length belongs to `executive_summary`'
check "description routes the genre-craft split to ghost_writer" \
  description_has "$SKILL" "craft standard.*belongs to \`ghost_writer\`"

for tag in role_and_activation role activation_triggers modes review_mode \
           rewrite_mode write_mode mode_selection mode_to_path_mapping \
           establish_the_reader fidelity_contract passes \
           pass_one_inventory_what_the_delivered_text_is_accountable_for \
           pass_two_produce_the_text_for_first_read_comprehension \
           pass_three_verify_the_delivered_text_against_the_ledger \
           output_contract review_mode_output rewrite_mode_output \
           write_mode_output shared_close selection_line \
           delivered_text_carries_content_only; do
  check "<$tag> block present" file_has "$SKILL" "^<$tag>"
done

for rule in keep_qualifiers_conditions_and_exceptions keep_requirement_strength \
            keep_every_specific_specific keep_the_reason_beside_the_claim \
            keep_the_connective_tissue keep_a_coherent_paragraph_as_prose \
            keep_open_questions_visible \
            keep_risks_commitments_and_constraints_at_full_force \
            keep_a_rewrite_within_the_draft_length \
            keep_the_reduction_uncapped_below_that_ceiling \
            keep_a_new_document_as_long_as_its_content_needs; do
  check "fidelity rule <$rule> present" section_has "$SKILL" fidelity_contract "^<$rule>"
done

check "the rewrite path is named in bold exactly once" \
  occurrences_are "$SKILL" '\*\*rewrite path\*\*' 1
check "the write path is named in bold exactly once" \
  occurrences_are "$SKILL" '\*\*write path\*\*' 1
check "mode-to-path mapping defines both paths" \
  section_has "$SKILL" mode_to_path_mapping '\*\*rewrite path\*\*.*\*\*write path\*\*'
check "pass one names both ledger inputs" \
  section_has "$SKILL" pass_one_inventory_what_the_delivered_text_is_accountable_for \
  'existing draft on the rewrite path, the supplied material on the write path'
check "pass two applies on both paths" \
  section_has "$SKILL" pass_two_produce_the_text_for_first_read_comprehension \
  'rewrite path and the write path alike'
check "pass three lets fidelity decide" \
  section_has "$SKILL" pass_three_verify_the_delivered_text_against_the_ledger 'fidelity decides'
check "a relocated claim keeps every joint attached to it" \
  section_has "$SKILL" keep_the_reason_beside_the_claim \
  'every joint attached to that claim travels with it'
check "every sentence carries a job the ledger assigns" \
  section_has "$SKILL" pass_two_produce_the_text_for_first_read_comprehension \
  'job the ledger assigns'
check "each ledger item has one home in the text" \
  section_has "$SKILL" pass_two_produce_the_text_for_first_read_comprehension \
  'one home in the text'

check "plugin README lists language_humanizer" file_has "$PLUGIN_README" '\*\*language_humanizer\*\*'
check "plugin README carries no em dash or en dash" file_lacks "$PLUGIN_README" '—|–'
check "root README lists language_humanizer" file_has "$ROOT_README" '\*\*language_humanizer\*\*'
check "root README ai_editorial section carries no em dash or en dash" root_section_lacks '—|–'

check_plugin_version_lockstep ai_editorial

# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox project, before any worker could start.
check "the eval runner's stage() raises on a failed or empty stage" \
  python3 "$REPO_ROOT/tests/lib/check_stage_guard.py" "$REPO_ROOT/tests/language_humanizer/evals"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if ((fail > 0)); then
  printf 'Failures:\n'
  printf '  - %s\n' "${failures[@]}"
  exit 1
fi
exit 0
