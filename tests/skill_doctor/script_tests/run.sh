#!/usr/bin/env bash
# Bundled-script unit tests for skill_doctor.
#
# Covers resolve_scope.py (layout discovery across the plugin, repo-root
# skills/, vendor-config, single-skill and lowercase-filename shapes, skipped
# directories, vendor-deploy substitution, plugin-manifest grouping,
# hub-with-<family> / prefix-only family resolution, structural <family> block
# location across the prose, fenced, unclosed, indented, commented,
# mid-sentence and mixed-case shapes, the by_plugin grouped view, and the
# three family drift warnings) and discovery_safety.py
# (the three severity tiers, the harness-derived byte limit, the ambiguous and
# non-regular skill file blocks, the convention-owned version info finding,
# risky sibling-description outliers, listing-budget description length, and
# the comparison group each sibling finding is measured inside — the
# cross-plugin coincidence split, the declared cross-plugin family, the
# one-plugin hubless prefix family, the no-grouping-argument default,
# walk-omitted given paths, the identical-purpose pair in both readings, and
# the unaffiliated whole-repo set). Also covers the shared skill_discovery
# module under both load paths, and the shipped SKILL.md static contract.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/skill_doctor"
SKILL_MD="$SKILL_DIR/SKILL.md"
RESOLVE="$SKILL_DIR/scripts/resolve_scope.py"
DISCOVERY="$SKILL_DIR/scripts/discovery_safety.py"
SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

check() {
  local id="$1"
  shift
  if "$@"; then
    PASS=$((PASS + 1))
    log "  PASS  $id"
  else
    FAIL=$((FAIL + 1))
    FAILED_IDS+=("$id")
    log "  FAIL  $id"
  fi
}

json_has() {
  local json="$1"
  local python_expr="$2"
  SKILL_DOCTOR_JSON="$json" python3 -c "
import json, os, sys
data = json.loads(os.environ['SKILL_DOCTOR_JSON'])
ok = bool($python_expr)
sys.exit(0 if ok else 1)
"
}

err_has() { printf '%s' "$1" | grep -qF "$2"; }
err_lacks() { ! printf '%s' "$1" | grep -qF "$2"; }

stage_repo() {
  local id="$1"
  local repo="$SCRATCH/$id/repo"
  rm -rf "${SCRATCH:?}/${id:?}"
  mkdir -p "$repo/plugins"
  printf '%s' "$repo"
}

write_skill() {
  local dir="$1"
  local name="$2"
  local description="$3"
  local body="${4:-}"
  mkdir -p "$dir"
  cat > "$dir/SKILL.md" <<EOF
---
name: ${name}
description: ${description}
version: 1.0.0
author: Test
license: MIT
---

# ${name}

${body}
EOF
}

# Compose a parse-safe description of an exact character length and write the
# SKILL.md carrying it. Length is the property under test, so the padding is
# ordinary prose: a repeated punctuation mark, a typographic dash or quote, or
# an invisible control character would trip the risky-punctuation,
# typographic-punctuation, hostile-character, or dual-audience checks that
# share the same run and muddy the finding under inspection.
write_skill_desc_len() {
  local dir="$1" name="$2" len="$3"
  mkdir -p "$dir"
  SD_DIR="$dir" SD_NAME="$name" SD_LEN="$len" python3 - <<'PY'
import os
from pathlib import Path

name = os.environ["SD_NAME"]
target = int(os.environ["SD_LEN"])
head = (
    f"Audit {name} widgets for correctness and packaging readiness. "
    f"Use when checking {name} widgets, widget metadata, or {name} "
    "release readiness. "
)
filler = (
    "The check walks every widget manifest in the selected set and reports "
    "each finding with a path and greppable evidence. "
)
desc = head
while len(desc) < target:
    desc += filler
desc = desc[:target]
if desc[-1].isspace():
    desc = desc[:-1] + "."
Path(os.environ["SD_DIR"], "SKILL.md").write_text(
    "---\n"
    f"name: {name}\n"
    f"description: {desc}\n"
    "version: 1.0.0\n"
    "author: Test\n"
    "license: MIT\n"
    "---\n"
    f"\n# {name}\n",
    encoding="utf-8",
)
PY
}

log "skill_doctor script_tests"
log ""

# --- Static SKILL.md contract ---------------------------------------------

check "skill_md_exists" test -f "$SKILL_MD"
check "frontmatter_name" grep -Eq '^name: skill_doctor$' "$SKILL_MD"
# Assert the shape, not a frozen value: the repo bumps this version with every
# commit that edits the skill, so pinning 1.0.0 fails on the next maintenance
# bump for a reason that has nothing to do with the contract under test.
check "frontmatter_version_semver" grep -Eq '^version: [0-9]+\.[0-9]+\.[0-9]+$' "$SKILL_MD"
check "description_check_only" grep -Eq '^description:.*[Cc]heck-only' "$SKILL_MD"
check "scope_single_family_all" \
  grep -Eq 'Single skill|Family|Whole repo' "$SKILL_MD"
check "name_target_set_before_checking" \
  grep -Eq 'name the final target set before' "$SKILL_MD"
check "discovery_safety_first" \
  grep -Eq 'Discovery safety is the first required check' "$SKILL_MD"
check "dual_audience_citation" \
  grep -Eq 'Write skill descriptions for both audiences' "$SKILL_MD"
check "check_only_no_edits" \
  grep -Eq 'byte-for-byte unchanged|never edits' "$SKILL_MD"
check "examples_three_scopes" \
  grep -Eq 'ai_instruction_writing' "$SKILL_MD" \
  && grep -Eq 'wiki family' "$SKILL_MD" \
  && grep -Eq 'all skills in this repo' "$SKILL_MD"
check "cites_formatting_and_writing" \
  grep -Eq 'ai_instruction_formatting' "$SKILL_MD" \
  && grep -Eq 'ai_instruction_writing' "$SKILL_MD"
check "no_copied_writing_core_rule" \
  bash -c "! grep -Eq 'Every instruction.s primary carrier is a positive statement' \"$SKILL_MD\""
check "harness_portability_boundary" \
  grep -Eq 'harness_portability' "$SKILL_MD"
check "report_blocking_first" \
  grep -Eq 'Blocking issues' "$SKILL_MD"
check "scripts_referenced" \
  grep -Eq 'scripts/resolve_scope.py' "$SKILL_MD" \
  && grep -Eq 'scripts/discovery_safety.py' "$SKILL_MD"
# The failure enumeration used to name three failures out of the resolver's
# eight exits, and to append candidate-naming as a blanket follow-through
# after every one of them. Both stale passages must stay gone.
check "no_stale_three_failure_enumeration" \
  bash -c "! grep -q 'three failures' \"$SKILL_MD\""
check "candidate_naming_scoped_to_unknown_name" \
  bash -c "! grep -q 'Name the nearest candidates the walk did find' \"$SKILL_MD\"" \
  && grep -q 'An unknown name' "$SKILL_MD" \
  && grep -q 'List the nearest candidates the walk did find, then ask which one the user means' "$SKILL_MD"
check "failure_classes_named_with_remedies" \
  grep -q 'An absent walk' "$SKILL_MD" \
  && grep -q 'A selector path fault' "$SKILL_MD" \
  && grep -q 'An environment or usage fault' "$SKILL_MD"
# The length dimension used to read as a sibling comparison only, which left a
# reader with a bare listing entry no diagnosis at all. The block now carries
# the budget arithmetic, the ranking that decides which description survives an
# overrun, and both causes of a name-only entry.
check "discovery_length_states_listing_budget_arithmetic" \
  grep -q 'skillListingBudgetFraction' "$SKILL_MD" \
  && grep -q 'skillListingMaxDescChars' "$SKILL_MD" \
  && grep -q 'recency-weighted usage score' "$SKILL_MD"
check "discovery_length_names_both_bare_entry_causes" \
  grep -q 'name-only' "$SKILL_MD" \
  && grep -q 'not from frontmatter the harness failed to parse' "$SKILL_MD"
check "discovery_length_is_not_a_sibling_comparison_only" \
  grep -q 'whether or not the run selected any siblings' "$SKILL_MD" \
  && grep -q 'listing-budget length, sibling length outliers' "$SKILL_MD"

# --- Static SKILL.md contract: portability across repo conventions --------
# The skill used to carry this repository's own conventions as hard
# requirements, which made a foreign repo's healthy skill draw findings that
# described a convention it never adopted. Each anchor below keeps one of those
# passages derived from the harness or from the checked repo instead.

# Section-scoped grep helper. A whole-file grep cannot say which block a
# string sits in, and every claim below is about one block.
section() {
  SD_MD="$SKILL_MD" SD_TAG="$1" python3 -c "
import os, re, sys
text = open(os.environ['SD_MD'], encoding='utf-8').read()
tag = os.environ['SD_TAG']
match = re.search(rf'<{tag}>(.*?)</{tag}>', text, re.DOTALL)
sys.stdout.write(match.group(1) if match else '')
"
}
section_has() { section "$1" | grep -qF "$2"; }
section_lacks() { ! section "$1" | grep -qF "$2"; }
# Paragraph-scoped variants. Paragraphs in this SKILL.md are single unwrapped
# lines, so the line carrying a bold lead-in is that whole tier's prose.
para_has() { section "$1" | grep -F "$2" | grep -qF "$3"; }
para_lacks() { ! section "$1" | grep -F "$2" | grep -qF "$3"; }
info_sits_between_warnings_and_summary() {
  section output_contract | python3 -c "
import sys
lines = sys.stdin.read().splitlines()
def find(needle):
    return next((i for i, line in enumerate(lines) if needle in line), None)
warn, info, summary = find('**Warnings**'), find('**Info**'), find('verification summary')
sys.exit(0 if None not in (warn, info, summary) and warn < info < summary else 1)
"
}

check "role_describes_any_skill_shipping_repo" \
  section_lacks role "plugin-shaped"
check "role_names_the_derivation_source" \
  section_has role "any repository that ships skills"

# The layout is discovered, so the resolution block names the shapes it
# recognizes rather than requiring one of them.
check "scope_resolution_discovers_the_layout" \
  section_has scope_resolution "discovers the layout instead of requiring one"
check "scope_resolution_reports_the_resolved_layout" \
  section_has scope_resolution "layouts"
# Agent handling used to read "Exclude agents unless the user names them.",
# which promised a named-agent behaviour no mechanism delivered: naming an
# agent fell through to the resolver and exited 2 as a missing skill. One
# skills-only statement replaces it, and the pre-resolver stop is what keeps
# that selector off the failure classes the block enumerates below.
check "scope_resolution_keeps_the_agent_statement" \
  section_lacks scope_resolution "Exclude agents unless the user names them." \
  && section_has scope_resolution "This skill checks skills only." \
  && section_has scope_resolution "stay outside every scope mode" \
  && section_has scope_resolution "plugins/*/agents/"
check "scope_resolution_routes_and_stops_on_a_named_agent" \
  section_has scope_resolution "before invoking \`scripts/resolve_scope.py\`" \
  && section_has scope_resolution "harness_portability" \
  && section_has scope_resolution "ai_instruction_writing" \
  && section_has scope_resolution "pre-resolver stop"
check "scope_resolution_names_the_empty_walk_message" \
  section_has scope_resolution "no SKILL.md found under"

# The family block is identified structurally, so an author may document the
# tag freely; the resolution block states that and the report shape names the
# grouping and the warnings the family run adds.
check "scope_resolution_locates_the_family_block_structurally" \
  section_has scope_resolution "structurally rather than by first occurrence" \
  && section_has scope_resolution "own its line" \
  && section_has scope_resolution "outside every fenced code block and inline code span"
check "scope_resolution_permits_documenting_the_tag" \
  section_has scope_resolution "document the tag freely"
check "scope_resolution_names_the_plugin_grouping" \
  section_has scope_resolution "by_plugin"
check "scope_resolution_names_the_three_family_warnings" \
  section_has scope_resolution "spanning more than one plugin" \
  && section_has scope_resolution "a prefix sibling the hub's parsed block omits" \
  && section_has scope_resolution "a block entry naming no discovered skill"
check "output_contract_lead_names_the_plugin_grouping" \
  section_has output_contract "grouped under the plugin that owns each member"
check "output_contract_warnings_carry_the_family_findings" \
  para_has output_contract "**Warnings**" "the resolver's family warnings"

# The parse fix is a decision a later reader could simplify back out, so the
# function states why it locates the block the way it does. It is defined in
# the shared discovery module now; resolve_scope.py re-exports the name, and a
# re-export is not a FunctionDef in that file.
family_parse_comment() {
  SD_SRC="$SKILL_DIR/scripts/skill_discovery.py" python3 -c "
import ast, os, sys
src = open(os.environ['SD_SRC'], encoding='utf-8').read()
tree = ast.parse(src)
node = next(
    (n for n in tree.body
     if isinstance(n, ast.FunctionDef) and n.name == 'parse_family_block_names'),
    None,
)
doc = ast.get_docstring(node) if node else ''
sys.exit(0 if doc and 'structurally rather than by first occurrence' in doc else 1)
"
}
check "parse_family_block_names_records_the_structural_choice" \
  family_parse_comment

# Three tiers, and a missing `version:` is not among the blocking conditions.
check "discovery_safety_documents_three_tiers" \
  section_has discovery_safety "**Blocking**" \
  && section_has discovery_safety "**Warning**" \
  && section_has discovery_safety "**Info**"
check "discovery_safety_blocking_list_omits_missing_version" \
  para_lacks discovery_safety "**Blocking**" "version"
check "discovery_safety_info_owns_missing_version" \
  para_has discovery_safety "**Info**" "\`version:\`"
check "discovery_safety_byte_limit_read_from_the_harness" \
  section_has discovery_safety "Skipping plugin skill ... byte limit" \
  && section_has discovery_safety "read out of the installed harness CLI at check time"
check "discovery_safety_name_mismatch_settled_by_the_load_path" \
  section_has discovery_safety "settled by reading the harness load path"

# The workflow records all three tiers, and the checks it runs come from the
# checked repository rather than from this one's Makefile inlined.
check "workflow_records_all_three_tiers" \
  para_has workflow "**Discovery safety first.**" \
  "Record blocking issues, warnings, and info-tier findings with paths and evidence"
check "workflow_registration_is_conditional" \
  section_has workflow "not applicable rather than as missing" \
  && section_has workflow "conditional on the checked repository's standing rule files stating that convention"
check "workflow_registration_reads_the_manifest_host" \
  section_has workflow "plugin_host"
check "workflow_verification_discovers_the_repos_own_checks" \
  section_has workflow "mise tasks" \
  && section_has workflow "pre-commit config" \
  && section_has workflow "Makefile"
check "workflow_verification_keeps_coverage_requirements" \
  section_has workflow "needs a script-test surface somewhere in the repo" \
  && section_has workflow "needs eval or trigger coverage or a documented reason it has none"
check "workflow_pseudo_xml_lint_is_conditional" \
  section_has workflow "when that sibling skill resolves" \
  && section_has workflow "name it as skipped with its reason when it does not"
# This repository's own deploy entry point and linter names are gone from the
# body; naming them made a foreign repo's verification step unrunnable.
check "workflow_names_no_repo_specific_entry_points" \
  bash -c "! grep -qF 'deployment.sh' \"$SKILL_MD\"" \
  && bash -c "! grep -qF 'markdownlint' \"$SKILL_MD\""

# The report carries the info tier between the warnings and the summary.
check "output_contract_orders_info_between_warnings_and_summary" \
  info_sits_between_warnings_and_summary
check "output_contract_info_names_its_rule_citation" \
  section_has output_contract "naming the rule the finding cites"
check "output_contract_lead_names_layout_and_substitution" \
  section_has output_contract "the layout the walk resolved" \
  && section_has output_contract "vendor-to-source substitution"
check "output_contract_summary_names_skip_reasons" \
  section_has output_contract "each with its reason"

# --- resolve_scope: hub with <family> union -------------------------------

HUB_REPO="$(stage_repo hub_family)"
mkdir -p "$HUB_REPO/plugins/demo/skills"
write_skill "$HUB_REPO/plugins/demo/skills/demo" "demo" \
  "Demo hub skill for family resolution tests. Use when testing hub family union." \
  "<demo>
<family>
- \`demo\` — hub
- \`demo_alpha\` — sibling
- \`shared_linter\` — named only in family block (no demo_ prefix)
</family>
</demo>"
write_skill "$HUB_REPO/plugins/demo/skills/demo_alpha" "demo_alpha" \
  "Demo alpha sibling. Use when testing prefix family membership."
write_skill "$HUB_REPO/plugins/demo/skills/shared_linter" "shared_linter" \
  "Shared linter named only via family block. Use when testing family union."
# Named lone_gizmo, not "other", to match the eval fixture: the eval grader
# scans response prose for this name, so an ordinary English word there matches
# unrelated sentences. Keep both surfaces on the same invented name.
write_skill "$HUB_REPO/plugins/demo/skills/lone_gizmo" "lone_gizmo" \
  "Standalone gizmo skill that shares no family token with the demo hub. Use when proving family resolution stops at the token boundary."
# Agent-shaped path must stay excluded from skill walk.
mkdir -p "$HUB_REPO/plugins/demo/agents"
printf '# agent\n' > "$HUB_REPO/plugins/demo/agents/auto_demo.md"

HUB_OUT="$("$RESOLVE" --root "$HUB_REPO" --family demo 2>/dev/null)" || true
check "hub_family_exit_json" \
  json_has "$HUB_OUT" "data.get('mode') == 'family' and data.get('count') == 3"
check "hub_family_includes_prefix_and_block" \
  json_has "$HUB_OUT" \
  "set(s['name'] for s in data['skills']) == {'demo', 'demo_alpha', 'shared_linter'}"
check "hub_family_excludes_unrelated" \
  json_has "$HUB_OUT" "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# --- resolve_scope: prefix-only (no <family> block) -----------------------

PREFIX_REPO="$(stage_repo prefix_only)"
mkdir -p "$PREFIX_REPO/plugins/km/skills"
write_skill "$PREFIX_REPO/plugins/km/skills/wiki" "wiki" \
  "Wiki hub without a family block. Use when testing prefix-only family resolution." \
  "<wiki>
<role>Hub without family enumeration.</role>
</wiki>"
write_skill "$PREFIX_REPO/plugins/km/skills/wiki_import" "wiki_import" \
  "Wiki import sibling. Use when testing prefix family membership."
write_skill "$PREFIX_REPO/plugins/km/skills/wiki_wrapup" "wiki_wrapup" \
  "Wiki wrapup sibling. Use when testing prefix family membership."
write_skill "$PREFIX_REPO/plugins/km/skills/spr" "spr" \
  "Unrelated distillation skill. Use when proving family exclusion."

PREFIX_OUT="$("$RESOLVE" --root "$PREFIX_REPO" --family wiki 2>/dev/null)" || true
check "prefix_only_count" \
  json_has "$PREFIX_OUT" "data.get('count') == 3"
check "prefix_only_names" \
  json_has "$PREFIX_OUT" \
  "set(s['name'] for s in data['skills']) == {'wiki', 'wiki_import', 'wiki_wrapup'}"
check "prefix_only_excludes_spr" \
  json_has "$PREFIX_OUT" "'spr' not in set(s['name'] for s in data['skills'])"

# Single-skill and --all smoke on the same fixture
SINGLE_OUT="$("$RESOLVE" --root "$PREFIX_REPO" --skill wiki_import 2>/dev/null)" || true
check "single_skill_resolution" \
  json_has "$SINGLE_OUT" \
  "data.get('mode') == 'skill' and data.get('count') == 1 and data['skills'][0]['name'] == 'wiki_import'"

ALL_OUT="$("$RESOLVE" --root "$PREFIX_REPO" --all 2>/dev/null)" || true
check "all_skills_resolution" \
  json_has "$ALL_OUT" "data.get('mode') == 'all' and data.get('count') == 4"

# --- resolve_scope: locating the <family> block ---------------------------
# The block is identified structurally, not by first occurrence: the opening
# tag owns its line outside every code span, and a closing tag has to follow.
# A hub is therefore free to document its own tag, which the shipped `task`
# hub does — its <not_in_scope> prose names `<family>` hundreds of lines above
# the real block, and a positional match ran from that mention to the nearest
# closing tag and harvested every backticked word in between.

# Call parse_family_block_names directly: the tri-state it returns (None for
# no block, [] for an empty one, names otherwise) is what gates the drift
# warnings, and resolve_family's filter against discovered skills hides it.
block_names() {
  SD_RESOLVE="$RESOLVE" SD_HUB="$1" python3 -c "
import importlib.util, json, os
from pathlib import Path
spec = importlib.util.spec_from_file_location('resolve_scope', os.environ['SD_RESOLVE'])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print(json.dumps(mod.parse_family_block_names(Path(os.environ['SD_HUB']))))
"
}

write_manifest() {
  mkdir -p "$1/.claude-plugin"
  printf '{"name": "%s", "version": "1.0.0"}\n' "$2" > "$1/.claude-plugin/plugin.json"
}

# Every block-location fixture shares one shape: a hub `demo`, a prefix
# sibling `demo_alpha` that membership never depends on the block for, a
# block-only member `shared_linter` whose presence proves the block parsed,
# and a decoy `lone_gizmo` that only a mis-located block would pull in.
stage_block_repo() {
  local id="$1" hub_body="$2"
  local repo="$SCRATCH/block/$id"
  rm -rf "$repo"
  write_skill "$repo/plugins/demo/skills/demo" "demo" \
    "Demo hub skill for family block location tests. Use when testing block location." \
    "$hub_body"
  write_skill "$repo/plugins/demo/skills/demo_alpha" "demo_alpha" \
    "Demo alpha sibling. Use when testing prefix family membership."
  write_skill "$repo/plugins/demo/skills/shared_linter" "shared_linter" \
    "Shared linter named only via family block. Use when testing family union."
  write_skill "$repo/plugins/demo/skills/lone_gizmo" "lone_gizmo" \
    "Standalone gizmo skill named only in hub prose. Use when proving a mention contributes no membership."
  printf '%s' "$repo"
}

# names the family resolves to, as a JSON-comparable set expression
block_case() {
  local id="$1" repo="$2" expect="$3"
  local out
  out="$("$RESOLVE" --root "$repo" --family demo 2>/dev/null)" || true
  check "block_${id}" \
    json_has "$out" "set(s['name'] for s in data['skills']) == $expect"
}

# 1. Prose naming `<family>` in backticks ahead of the real block.
BLOCK_PROSE_BEFORE="$(stage_block_repo prose_before '<demo>
<not_in_scope>
A sibling serves some of that work better than the hub does, which `<family>`
names alongside every other sibling role. Routing there leaves `lone_gizmo`
out of the family entirely.
</not_in_scope>

<family>
- `shared_linter` — declared member
</family>
</demo>')"
block_case "prose_before_block_resolves_the_real_members" "$BLOCK_PROSE_BEFORE" \
  "{'demo', 'demo_alpha', 'shared_linter'}"
check "block_prose_before_block_excludes_the_prose_name" \
  json_has "$("$RESOLVE" --root "$BLOCK_PROSE_BEFORE" --family demo 2>/dev/null)" \
  "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# 2. The same mention, after the block.
BLOCK_PROSE_AFTER="$(stage_block_repo prose_after '<demo>
<family>
- `shared_linter` — declared member
</family>

<not_in_scope>
The `<family>` block above names the set; `lone_gizmo` sits outside it.
</not_in_scope>
</demo>')"
block_case "prose_after_block_resolves_the_real_members" "$BLOCK_PROSE_AFTER" \
  "{'demo', 'demo_alpha', 'shared_linter'}"
check "block_prose_after_block_excludes_the_prose_name" \
  json_has "$("$RESOLVE" --root "$BLOCK_PROSE_AFTER" --family demo 2>/dev/null)" \
  "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# 3. A fenced example ahead of the real block.
BLOCK_FENCE_BEFORE="$(stage_block_repo fence_before '<demo>
Authors declare the set like this:

```text
<family>
- `lone_gizmo` — sample entry, not a real member
</family>
```

<family>
- `shared_linter` — declared member
</family>
</demo>')"
block_case "fenced_example_ahead_resolves_the_real_members" "$BLOCK_FENCE_BEFORE" \
  "{'demo', 'demo_alpha', 'shared_linter'}"
check "block_fenced_example_ahead_excludes_the_sample_name" \
  json_has "$("$RESOLVE" --root "$BLOCK_FENCE_BEFORE" --family demo 2>/dev/null)" \
  "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# 4. A fenced example inside the genuine block. Harvest reads inline code, so
#    the fence has to be blanked before entries are read or its sample names
#    become members.
BLOCK_FENCE_INSIDE="$(stage_block_repo fence_inside '<demo>
<family>
- `shared_linter` — declared member

An entry looks like this:

```text
- `lone_gizmo` — sample entry, not a real member
```
</family>
</demo>')"
block_case "fenced_example_inside_resolves_the_real_members" "$BLOCK_FENCE_INSIDE" \
  "{'demo', 'demo_alpha', 'shared_linter'}"
check "block_fenced_example_inside_excludes_the_sample_name" \
  json_has "$("$RESOLVE" --root "$BLOCK_FENCE_INSIDE" --family demo 2>/dev/null)" \
  "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# 5. An opening tag with no closing tag declares no block at all, so the
#    family falls back to the prefix set rather than running to end of body.
BLOCK_UNCLOSED="$(stage_block_repo unclosed '<demo>
This hub documents `<family>` in prose and never closes the tag below.

<family>
- `shared_linter` — would be a member if the block closed
- `lone_gizmo` — likewise
</demo>')"
block_case "unclosed_tag_falls_back_to_the_prefix_set" "$BLOCK_UNCLOSED" \
  "{'demo', 'demo_alpha'}"
check "block_unclosed_tag_parses_no_block" \
  test "$(block_names "$BLOCK_UNCLOSED/plugins/demo/skills/demo/SKILL.md")" = "null"

# 6. An indented block.
BLOCK_INDENTED="$(stage_block_repo indented '<demo>
  <family>
  - `shared_linter` — declared member
  </family>
</demo>')"
block_case "indented_block_resolves_its_members" "$BLOCK_INDENTED" \
  "{'demo', 'demo_alpha', 'shared_linter'}"

# 7. An opening tag carrying a trailing HTML comment.
BLOCK_COMMENTED="$(stage_block_repo commented '<demo>
<family> <!-- the sibling set -->
- `shared_linter` — declared member
</family>
</demo>')"
block_case "commented_open_tag_resolves_its_members" "$BLOCK_COMMENTED" \
  "{'demo', 'demo_alpha', 'shared_linter'}"

# 8. An unbackticked mid-sentence mention, which masking alone cannot cover —
#    the line-owning requirement is what excludes it. The decoy list item
#    between the mention and the real block is what a positional match ate.
BLOCK_MIDSENTENCE="$(stage_block_repo midsentence '<demo>
The <family> tag names the sibling set. Skills outside it include:

- `lone_gizmo` — a prose list item, not a family entry

<family>
- `shared_linter` — declared member
</family>
</demo>')"
block_case "unbackticked_mention_resolves_the_real_members" "$BLOCK_MIDSENTENCE" \
  "{'demo', 'demo_alpha', 'shared_linter'}"
check "block_unbackticked_mention_excludes_the_prose_list_item" \
  json_has "$("$RESOLVE" --root "$BLOCK_MIDSENTENCE" --family demo 2>/dev/null)" \
  "'lone_gizmo' not in set(s['name'] for s in data['skills'])"

# 9. A member is the leading backticked token of its list item. A trailing
#    backticked word in the same entry's prose is description, not a member.
BLOCK_TRAILING="$(stage_block_repo trailing_backtick '<demo>
<family>
- `sib_one` — does a thing, bumps `updated`
- `shared_linter` — declared member
</family>
</demo>')"
TRAILING_NAMES="$(block_names "$BLOCK_TRAILING/plugins/demo/skills/demo/SKILL.md")"
check "block_entry_yields_only_its_leading_token" \
  test "$TRAILING_NAMES" = '["sib_one", "shared_linter"]'
check "block_entry_excludes_a_trailing_backticked_word" \
  bash -c "! printf '%s' '$TRAILING_NAMES' | grep -q 'updated'"

# 10. The tags match case-insensitively, as the prior regex did.
BLOCK_MIXED_CASE="$(stage_block_repo mixed_case '<demo>
<Family>
- `shared_linter` — declared member
</FAMILY>
</demo>')"
block_case "mixed_case_tags_resolve_their_members" "$BLOCK_MIXED_CASE" \
  "{'demo', 'demo_alpha', 'shared_linter'}"

# The shipped `task` hub is the real case the parse fix exists for.
TASK_HUB_NAMES="$(block_names "$REPO_ROOT/plugins/ai_dev/skills/task/SKILL.md")"
check "shipped_task_hub_harvests_only_prefixed_siblings" \
  env SD_NAMES="$TASK_HUB_NAMES" python3 -c "
import json, os, sys
names = json.loads(os.environ['SD_NAMES'])
sys.exit(0 if names and all(n.startswith('task_') for n in names) else 1)
"
check "shipped_task_hub_excludes_the_hub_name_and_prose_words" \
  bash -c "! printf '%s' '$TASK_HUB_NAMES' | grep -qE '\"(task|updated|open|ready|mv)\"'"
# The skill_doctor hub names `<family>` with no closing tag anywhere, which is
# the shape that must resolve to no block rather than to end of body.
check "shipped_skill_doctor_hub_parses_no_block" \
  test "$(block_names "$SKILL_MD")" = "null"

SELF_TASK_OUT="$("$RESOLVE" --root "$REPO_ROOT" --family task 2>/dev/null)" || true
check "shipped_task_family_is_exactly_the_prefixed_set" \
  json_has "$SELF_TASK_OUT" \
  "set(s['name'] for s in data['skills']) == \
   set(s['name'] for s in data['skills'] \
       if s['name'] == 'task' or s['name'].startswith('task_'))"
check "shipped_task_family_drops_the_contaminating_wiki_name" \
  json_has "$SELF_TASK_OUT" "'wiki' not in set(s['name'] for s in data['skills'])"
check "shipped_task_family_output_mentions_no_wiki" \
  bash -c "! printf '%s' \"\$1\" | grep -q wiki" _ "$SELF_TASK_OUT"
# The two other family hubs this repository ships keep their membership.
SELF_GUARDRAIL_OUT="$("$RESOLVE" --root "$REPO_ROOT" --family guardrail 2>/dev/null)" || true
check "shipped_guardrail_family_unchanged" \
  json_has "$SELF_GUARDRAIL_OUT" \
  "set(s['name'] for s in data['skills']) == {'guardrail', 'guardrail_audit'}"
SELF_WIKI_OUT="$("$RESOLVE" --root "$REPO_ROOT" --family wiki 2>/dev/null)" || true
check "shipped_wiki_family_unchanged" \
  json_has "$SELF_WIKI_OUT" \
  "set(s['name'] for s in data['skills']) == \
   {'wiki', 'wiki_fix', 'wiki_import', 'wiki_wrapup'}"
check "shipped_task_family_warnings_present_and_clean" \
  json_has "$SELF_TASK_OUT" \
  "isinstance(data.get('warnings'), list) and not [ \
     w for w in data['warnings'] \
     if w['code'] in ('family_block_omits_sibling', 'family_block_entry_unknown')]"

# --- resolve_scope: grouping the resolved set by owning plugin ------------

GROUP_REPO="$(stage_repo by_plugin)"
write_manifest "$GROUP_REPO/plugins/one" one
write_skill "$GROUP_REPO/plugins/one/skills/db_query" "db_query" \
  "Audit db query widgets for correctness. Use when checking db query widgets or widget metadata."
write_skill "$GROUP_REPO/plugins/one/skills/db_index" "db_index" \
  "Audit db index widgets for correctness. Use when checking db index widgets or widget metadata."
GROUP_OUT="$("$RESOLVE" --root "$GROUP_REPO" --family db 2>/dev/null)" || true
check "by_plugin_groups_hosted_members" \
  json_has "$GROUP_OUT" \
  "data.get('by_plugin') == {'plugins/one': ['db_index', 'db_query']}"
check "by_plugin_keeps_the_flat_skills_array" \
  json_has "$GROUP_OUT" \
  "set(s['name'] for s in data['skills']) == {'db_index', 'db_query'}"
GROUP_LEAD="$("$RESOLVE" --root "$GROUP_REPO" --family db 2>&1 >/dev/null)"
check "orientation_lead_groups_members_under_their_plugin" \
  err_has "$GROUP_LEAD" "plugins/one [db_index, db_query]"

# A family with no plugin manifest above it: the members stay in the flat
# array and are omitted from the grouped view, which is what lets the
# registration step call the surface not applicable instead of missing.
NOHOST_REPO="$(stage_repo by_plugin_nohost)"
write_skill "$NOHOST_REPO/plugins/loose/skills/db_query" "db_query" \
  "Audit db query widgets for correctness. Use when checking db query widgets or widget metadata."
write_skill "$NOHOST_REPO/plugins/loose/skills/db_index" "db_index" \
  "Audit db index widgets for correctness. Use when checking db index widgets or widget metadata."
NOHOST_OUT="$("$RESOLVE" --root "$NOHOST_REPO" --family db 2>/dev/null)" || true
check "by_plugin_omits_members_with_no_plugin_host" \
  json_has "$NOHOST_OUT" "data.get('by_plugin') == {}"
check "no_plugin_host_members_stay_in_the_flat_array" \
  json_has "$NOHOST_OUT" \
  "data.get('count') == 2 and \
   all(s['plugin_host'] is None for s in data['skills'])"
NOHOST_LEAD="$("$RESOLVE" --root "$NOHOST_REPO" --family db 2>&1 >/dev/null)"
check "orientation_lead_labels_unhosted_members" \
  err_has "$NOHOST_LEAD" "no plugin manifest [db_index, db_query]"

# --- resolve_scope: family drift warnings ---------------------------------
# Three findings, all at warning: the harness loads every one of these skills,
# and a hub may deliberately omit a deprecated sibling, so none of them is a
# mechanical load failure.

warning_codes() {
  json_has "$1" "[w['code'] for w in data.get('warnings', [])] == $2"
}
has_warning() {
  json_has "$1" "any(w['code'] == '$2' for w in data.get('warnings', []))"
}
lacks_warning() {
  json_has "$1" "not any(w['code'] == '$2' for w in data.get('warnings', []))"
}

# 11. A prefix family spanning two plugins. The members stay in the resolved
#     set — a genuine cross-plugin family is what the block's union serves —
#     and the split is named instead of assumed either way.
SPAN_REPO="$(stage_repo family_spans)"
write_manifest "$SPAN_REPO/plugins/one" one
write_manifest "$SPAN_REPO/plugins/two" two
write_skill "$SPAN_REPO/plugins/one/skills/db_query" "db_query" \
  "Audit db query widgets for correctness. Use when checking db query widgets or widget metadata."
write_skill "$SPAN_REPO/plugins/two/skills/db_migrate" "db_migrate" \
  "Audit db migrate widgets for correctness. Use when checking db migrate widgets or widget metadata."
SPAN_OUT="$("$RESOLVE" --root "$SPAN_REPO" --family db 2>/dev/null)" || true
check "cross_plugin_family_warns" has_warning "$SPAN_OUT" family_spans_plugins
check "cross_plugin_warning_names_both_plugins" \
  json_has "$SPAN_OUT" \
  "[p['directory'] for w in data['warnings'] \
    if w['code'] == 'family_spans_plugins' for p in w['plugins']] \
   == ['plugins/one', 'plugins/two']"
check "cross_plugin_warning_names_the_skills_and_paths" \
  json_has "$SPAN_OUT" \
  "[(s['name'], s['path']) for w in data['warnings'] \
    if w['code'] == 'family_spans_plugins' for s in w['skills']] \
   == [('db_query', 'plugins/one/skills/db_query/SKILL.md'), \
       ('db_migrate', 'plugins/two/skills/db_migrate/SKILL.md')]"
check "cross_plugin_warning_stays_a_warning" \
  json_has "$SPAN_OUT" \
  "all(w['severity'] == 'warning' for w in data['warnings'])"
check "cross_plugin_family_keeps_both_members" \
  json_has "$SPAN_OUT" \
  "set(s['name'] for s in data['skills']) == {'db_query', 'db_migrate'}"
SPAN_LEAD="$("$RESOLVE" --root "$SPAN_REPO" --family db 2>&1 >/dev/null)"
check "cross_plugin_warning_reaches_stderr" \
  err_has "$SPAN_LEAD" "family_spans_plugins"

# 12. The same prefix wholly inside one plugin draws no split warning.
check "one_plugin_family_does_not_warn_on_a_split" \
  lacks_warning "$GROUP_OUT" family_spans_plugins

# 13/14. A null-host same-prefix skill alongside a one-plugin family is not a
#     split: the span is measured over hosted members only.
MIXEDHOST_REPO="$(stage_repo family_mixed_host)"
write_manifest "$MIXEDHOST_REPO/plugins/one" one
write_skill "$MIXEDHOST_REPO/plugins/one/skills/db_query" "db_query" \
  "Audit db query widgets for correctness. Use when checking db query widgets or widget metadata."
write_skill "$MIXEDHOST_REPO/plugins/one/skills/db_index" "db_index" \
  "Audit db index widgets for correctness. Use when checking db index widgets or widget metadata."
write_skill "$MIXEDHOST_REPO/skills/db_loose" "db_loose" \
  "Audit db loose widgets for correctness. Use when checking db loose widgets or widget metadata."
MIXEDHOST_OUT="$("$RESOLVE" --root "$MIXEDHOST_REPO" --family db 2>/dev/null)" || true
check "null_host_member_does_not_trigger_a_split_warning" \
  lacks_warning "$MIXEDHOST_OUT" family_spans_plugins
check "null_host_member_stays_in_the_resolved_set" \
  json_has "$MIXEDHOST_OUT" \
  "set(s['name'] for s in data['skills']) == {'db_index', 'db_loose', 'db_query'} \
   and data['by_plugin'] == {'plugins/one': ['db_index', 'db_query']}"
check "no_plugin_host_family_draws_no_split_warning" \
  lacks_warning "$NOHOST_OUT" family_spans_plugins

# A hub with a block, staged so each drift case differs only in that block.
stage_drift_repo() {
  local id="$1" block="$2"
  local repo="$SCRATCH/drift/$id"
  rm -rf "$repo"
  write_manifest "$repo/plugins/demo" demo
  write_skill "$repo/plugins/demo/skills/demo" "demo" \
    "Demo hub skill for family drift tests. Use when testing family drift warnings." \
    "$block"
  write_skill "$repo/plugins/demo/skills/demo_alpha" "demo_alpha" \
    "Demo alpha sibling. Use when testing prefix family membership."
  write_skill "$repo/plugins/demo/skills/demo_beta" "demo_beta" \
    "Demo beta sibling. Use when testing prefix family membership."
  printf '%s' "$repo"
}

# 15. A block that omits a prefix sibling reads as documentation behind the
#     tree. The omitted sibling stays in the resolved set.
OMIT_REPO="$(stage_drift_repo omits_sibling '<demo>
<family>
- `demo_alpha` — declared member
</family>
</demo>')"
OMIT_OUT="$("$RESOLVE" --root "$OMIT_REPO" --family demo 2>/dev/null)" || true
check "block_omitting_a_sibling_warns" \
  has_warning "$OMIT_OUT" family_block_omits_sibling
check "omit_warning_names_the_missing_sibling_and_path" \
  json_has "$OMIT_OUT" \
  "[(s['name'], s['path']) for w in data['warnings'] \
    if w['code'] == 'family_block_omits_sibling' for s in w['skills']] \
   == [('demo_beta', 'plugins/demo/skills/demo_beta/SKILL.md')]"
check "omit_warning_keeps_the_sibling_in_the_resolved_set" \
  json_has "$OMIT_OUT" \
  "set(s['name'] for s in data['skills']) == {'demo', 'demo_alpha', 'demo_beta'}"

# 16. A block entry naming no discovered skill reads as a member renamed or
#     removed.
DANGLE_REPO="$(stage_drift_repo dangling_entry '<demo>
<family>
- `demo_alpha` — declared member
- `demo_beta` — declared member
- `demo_ghost` — renamed away or removed
</family>
</demo>')"
DANGLE_OUT="$("$RESOLVE" --root "$DANGLE_REPO" --family demo 2>/dev/null)" || true
check "block_entry_naming_no_skill_warns" \
  has_warning "$DANGLE_OUT" family_block_entry_unknown
check "dangling_warning_names_the_entry" \
  json_has "$DANGLE_OUT" \
  "[w['entry'] for w in data['warnings'] \
    if w['code'] == 'family_block_entry_unknown'] == ['demo_ghost']"
check "dangling_warning_names_the_declaring_hub_and_path" \
  json_has "$DANGLE_OUT" \
  "[(s['name'], s['path']) for w in data['warnings'] \
    if w['code'] == 'family_block_entry_unknown' for s in w['skills']] \
   == [('demo', 'plugins/demo/skills/demo/SKILL.md')]"
check "dangling_entry_draws_no_omit_warning" \
  lacks_warning "$DANGLE_OUT" family_block_omits_sibling

# 17. A block listing every prefix sibling is clean, including when it leaves
#     the hub's own name out — the hub is not a sibling whose absence warns.
COMPLETE_REPO="$(stage_drift_repo complete_block '<demo>
<family>
- `demo_alpha` — declared member
- `demo_beta` — declared member
</family>
</demo>')"
COMPLETE_OUT="$("$RESOLVE" --root "$COMPLETE_REPO" --family demo 2>/dev/null)" || true
check "complete_block_omitting_the_hub_name_draws_no_warning" \
  warning_codes "$COMPLETE_OUT" "[]"
HUBNAMED_REPO="$(stage_drift_repo hub_named_block '<demo>
<family>
- `demo` — hub
- `demo_alpha` — declared member
- `demo_beta` — declared member
</family>
</demo>')"
HUBNAMED_OUT="$("$RESOLVE" --root "$HUBNAMED_REPO" --family demo 2>/dev/null)" || true
check "complete_block_naming_the_hub_draws_no_warning" \
  warning_codes "$HUBNAMED_OUT" "[]"

# 18. A hub with no parsed block resolves by prefix alone and produces
#     neither drift finding — there is no declaration to disagree with.
NOBLOCK_REPO="$(stage_drift_repo no_block '<demo>
<role>Hub that documents `<family>` without declaring one.</role>
</demo>')"
NOBLOCK_OUT="$("$RESOLVE" --root "$NOBLOCK_REPO" --family demo 2>/dev/null)" || true
check "hub_with_no_block_draws_neither_drift_warning" \
  warning_codes "$NOBLOCK_OUT" "[]"
check "hub_with_no_block_resolves_by_prefix" \
  json_has "$NOBLOCK_OUT" \
  "set(s['name'] for s in data['skills']) == {'demo', 'demo_alpha', 'demo_beta'}"

# --- resolve_scope: an empty walk -----------------------------------------
# The walk finding no skill file anywhere is one failure with one message in
# every scope mode. A selector cannot miss inside a tree that is not there, so
# an unknown-name message here would send the reader after a typo instead of
# the real cause, and its remedy (name the nearest candidates) has no
# candidates to name. The message names the root that was walked, since the
# layout is now discovered rather than required, so "which tree" is the
# reader's first question. Two shapes reach the condition: a repo with no
# skill-bearing directory at all, and a skills tree that holds no skill.

ABSENT_MSG='no SKILL.md found under '
STALE_ABSENT_MSG='no skills found under plugins/*/skills/'
UNKNOWN_SKILL_MSG='skill not found:'
UNKNOWN_FAMILY_MSG='no skills found for family token:'

resolved_path() {
  python3 -c "import pathlib,sys; print(pathlib.Path(sys.argv[1]).resolve())" "$1"
}

absent_layout_case() {
  local label="$1" repo="$2" id="$3"
  shift 3
  local err rc
  err="$("$RESOLVE" --root "$repo" "$@" 2>&1 >/dev/null)"
  rc=$?
  check "absent_tree_${label}_${id}_reports_absent_layout" \
    err_has "$err" "$ABSENT_MSG"
  check "absent_tree_${label}_${id}_names_the_walked_root" \
    err_has "$err" "${ABSENT_MSG}$(resolved_path "$repo")"
  check "absent_tree_${label}_${id}_exits_nonzero" test "$rc" -ne 0
  check "absent_tree_${label}_${id}_not_stale_layout_message" \
    err_lacks "$err" "$STALE_ABSENT_MSG"
  check "absent_tree_${label}_${id}_not_unknown_skill" \
    err_lacks "$err" "$UNKNOWN_SKILL_MSG"
  check "absent_tree_${label}_${id}_not_unknown_family" \
    err_lacks "$err" "$UNKNOWN_FAMILY_MSG"
}

absent_layout_scenarios() {
  local label="$1" repo="$2"
  absent_layout_case "$label" "$repo" skill_name --skill foo
  absent_layout_case "$label" "$repo" skill_path --skill orphan/myskill
  absent_layout_case "$label" "$repo" family --family foo
  absent_layout_case "$label" "$repo" all --all
}

# Shape 1: no skill-bearing directory at all. stage_repo creates plugins/, so
# this fixture is built by hand.
NO_PLUGINS_REPO="$SCRATCH/absent_no_plugins/repo"
rm -rf "${SCRATCH:?}/absent_no_plugins"
mkdir -p "$NO_PLUGINS_REPO"
printf '# repo with no plugins tree\n' > "$NO_PLUGINS_REPO/README.md"
absent_layout_scenarios no_plugins "$NO_PLUGINS_REPO"

# Shape 2: a skills tree present and holding no skill file.
EMPTY_SKILLS_REPO="$SCRATCH/absent_empty_skills/repo"
rm -rf "${SCRATCH:?}/absent_empty_skills"
mkdir -p "$EMPTY_SKILLS_REPO/plugins/demo/skills"
absent_layout_scenarios empty_skills "$EMPTY_SKILLS_REPO"

# The superseded message must be gone from the shipped surfaces too, so a
# reader grepping either one lands on the message the resolver now emits.
check "no_stale_absent_layout_message_in_skill_md" \
  bash -c "! grep -qF '$STALE_ABSENT_MSG' \"$SKILL_MD\""
check "no_stale_absent_layout_message_in_resolver" \
  bash -c "! grep -qF '$STALE_ABSENT_MSG' \"$RESOLVE\""

# --- resolve_scope: selector misses inside a present tree -----------------
# The counterpart guard. With the tree in place, an unknown name keeps the
# candidate-naming remedy and a bad path keeps the path-fault message, so the
# pre-dispatch absent-layout check stays scoped to the tree-is-absent case.

UNKNOWN_SKILL_ERR="$("$RESOLVE" --root "$PREFIX_REPO" --skill omega_flange 2>&1 >/dev/null)"
unknown_skill_rc=$?
check "unknown_skill_in_present_tree_message" \
  err_has "$UNKNOWN_SKILL_ERR" "skill not found: omega_flange"
check "unknown_skill_in_present_tree_exits_nonzero" test "$unknown_skill_rc" -ne 0
check "unknown_skill_in_present_tree_not_absent_layout" \
  err_lacks "$UNKNOWN_SKILL_ERR" "$ABSENT_MSG"

UNKNOWN_FAMILY_ERR="$("$RESOLVE" --root "$PREFIX_REPO" --family omega 2>&1 >/dev/null)"
unknown_family_rc=$?
check "unknown_family_in_present_tree_message" \
  err_has "$UNKNOWN_FAMILY_ERR" "no skills found for family token: omega"
check "unknown_family_in_present_tree_exits_nonzero" test "$unknown_family_rc" -ne 0
check "unknown_family_in_present_tree_not_absent_layout" \
  err_lacks "$UNKNOWN_FAMILY_ERR" "$ABSENT_MSG"

BAD_PATH_ERR="$("$RESOLVE" --root "$PREFIX_REPO" --skill plugins/km/skills/omega 2>&1 >/dev/null)"
bad_path_rc=$?
check "bad_path_in_present_tree_message" \
  err_has "$BAD_PATH_ERR" "skill path not found: plugins/km/skills/omega"
check "bad_path_in_present_tree_exits_nonzero" test "$bad_path_rc" -ne 0
check "bad_path_in_present_tree_not_absent_layout" \
  err_lacks "$BAD_PATH_ERR" "$ABSENT_MSG"

# --- resolve_scope: layouts other than plugins/*/skills/ ------------------
# The walk discovers the layout instead of requiring one, so a repo that keeps
# its skills anywhere else still resolves and still reports what was walked.
# Each fixture holds exactly one skill so a miscounted walk fails loudly.

LAYOUTS="$SCRATCH/layouts"
rm -rf "${SCRATCH:?}/layouts"

layout_case() {
  local id="$1" repo="$2" expect_layout="$3" expect_path="$4"
  local out
  out="$("$RESOLVE" --root "$repo" --all 2>/dev/null)" || true
  check "layout_${id}_all_resolves_one_skill" \
    json_has "$out" "data.get('count') == 1"
  check "layout_${id}_all_names_the_layout" \
    json_has "$out" \
    "[l['layout'] for l in data['layouts']] == ['$expect_layout'] \
     and data['skills'][0]['layout'] == '$expect_layout'"
  check "layout_${id}_all_resolves_the_expected_path" \
    json_has "$out" "data['skills'][0]['path'] == '$expect_path'"
  out="$("$RESOLVE" --root "$repo" --family demo 2>/dev/null)" || true
  check "layout_${id}_family_resolves_and_names_the_layout" \
    json_has "$out" \
    "data.get('count') == 1 and data['skills'][0]['name'] == 'demo' \
     and [l['layout'] for l in data['layouts']] == ['$expect_layout']"
  out="$("$RESOLVE" --root "$repo" --skill demo 2>/dev/null)" || true
  check "layout_${id}_single_skill_resolves" \
    json_has "$out" \
    "data.get('count') == 1 and data['skills'][0]['path'] == '$expect_path'"
}

write_skill "$LAYOUTS/repo_skills/skills/demo" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
layout_case repo_skills "$LAYOUTS/repo_skills" repo_skills "skills/demo/SKILL.md"

write_skill "$LAYOUTS/vendor_config/.claude/skills/demo" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
layout_case vendor_config "$LAYOUTS/vendor_config" vendor_config_skills \
  ".claude/skills/demo/SKILL.md"

# A single-skill repo: the SKILL.md sits at the top level, so the skill takes
# its name from frontmatter rather than from a containing skill directory.
mkdir -p "$LAYOUTS/single_skill"
write_skill "$LAYOUTS/single_skill" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
layout_case single_skill "$LAYOUTS/single_skill" single_skill "SKILL.md"

# The harness matches the skill filename case-insensitively, so a repo that
# writes it lowercase resolves the same way — including when the selector
# names that exact path.
write_skill "$LAYOUTS/lowercase/skills/demo" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
mv "$LAYOUTS/lowercase/skills/demo/SKILL.md" "$LAYOUTS/lowercase/skills/demo/skill.md"
layout_case lowercase "$LAYOUTS/lowercase" repo_skills "skills/demo/skill.md"
LOWER_PATH_OUT="$("$RESOLVE" --root "$LAYOUTS/lowercase" \
  --skill skills/demo/skill.md 2>/dev/null)" || true
check "layout_lowercase_path_selector_resolves" \
  json_has "$LOWER_PATH_OUT" \
  "data.get('count') == 1 and data['skills'][0]['path'] == 'skills/demo/skill.md'"

# Version-control, dependency, build and cache directories hold no skill a
# repository authors, so the walk prunes them.
write_skill "$LAYOUTS/skipdirs/skills/visible" "visible" \
  "Audit visible widgets for correctness and readiness. Use when checking visible widgets or widget metadata."
write_skill "$LAYOUTS/skipdirs/node_modules/dep/skills/vendored" "vendored" \
  "Audit vendored widgets for correctness and readiness. Use when checking vendored widgets or widget metadata."
write_skill "$LAYOUTS/skipdirs/.git/skills/ghost" "ghost" \
  "Audit ghost widgets for correctness and readiness. Use when checking ghost widgets or widget metadata."
write_skill "$LAYOUTS/skipdirs/__pycache__/cached" "cached" \
  "Audit cached widgets for correctness and readiness. Use when checking cached widgets or widget metadata."
SKIPDIRS_OUT="$("$RESOLVE" --root "$LAYOUTS/skipdirs" --all 2>/dev/null)" || true
check "layout_skipped_dirs_returns_only_the_visible_skill" \
  json_has "$SKIPDIRS_OUT" \
  "set(s['name'] for s in data['skills']) == {'visible'}"

# A deployed copy under a harness configuration directory outside the repo
# root is a build output, so the selector resolves the repository source it
# came from and the payload names the substitution for the orientation lead.
write_skill "$LAYOUTS/vendor_deploy/repo/skills/demo" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
write_skill "$LAYOUTS/vendor_deploy/home/.claude/skills/demo" "demo" \
  "Audit demo widgets for correctness and readiness. Use when checking demo widgets or widget metadata."
VENDOR_OUT="$("$RESOLVE" --root "$LAYOUTS/vendor_deploy/repo" \
  --skill "$LAYOUTS/vendor_deploy/home/.claude/skills/demo/SKILL.md" 2>/dev/null)" || true
check "vendor_selector_resolves_the_repo_source" \
  json_has "$VENDOR_OUT" \
  "data.get('count') == 1 and data['skills'][0]['path'] == 'skills/demo/SKILL.md'"
check "vendor_selector_names_the_substitution" \
  json_has "$VENDOR_OUT" \
  "(data.get('vendor_substitution') or {}).get('vendor_dir') == '.claude' \
   and (data.get('vendor_substitution') or {}).get('skill_name') == 'demo'"
VENDOR_ERR="$("$RESOLVE" --root "$LAYOUTS/vendor_deploy/repo" \
  --skill "$LAYOUTS/vendor_deploy/home/.claude/skills/demo/SKILL.md" 2>&1 >/dev/null)"
check "vendor_substitution_reaches_the_orientation_lead" \
  err_has "$VENDOR_ERR" "Vendor deploy substitution"
# A plain in-repo selector reports no substitution, so the field stays a
# signal rather than noise.
NO_VENDOR_OUT="$("$RESOLVE" --root "$LAYOUTS/vendor_deploy/repo" \
  --skill demo 2>/dev/null)" || true
check "in_repo_selector_reports_no_substitution" \
  json_has "$NO_VENDOR_OUT" "data.get('vendor_substitution') is None"

# The registration step needs to know which plugin manifest owns a skill, so
# the walk records the nearest manifest above it.
write_skill "$LAYOUTS/manifest/plugins/demo/skills/foo" "foo" \
  "Audit foo widgets for correctness and readiness. Use when checking foo widgets or widget metadata."
mkdir -p "$LAYOUTS/manifest/plugins/demo/.claude-plugin"
printf '{"name": "demo", "version": "1.0.0"}\n' \
  > "$LAYOUTS/manifest/plugins/demo/.claude-plugin/plugin.json"
MANIFEST_OUT="$("$RESOLVE" --root "$LAYOUTS/manifest" --skill foo 2>/dev/null)" || true
check "manifest_host_named_for_the_owned_skill" \
  json_has "$MANIFEST_OUT" \
  "data['skills'][0]['plugin_host']['manifests'] == \
   ['plugins/demo/.claude-plugin/plugin.json']"
check "manifest_host_directory_named" \
  json_has "$MANIFEST_OUT" \
  "data['skills'][0]['plugin_host']['directory'] == 'plugins/demo'"
# A repo with no manifest reports no host, which is what lets the
# registration step call the surface not applicable instead of missing.
NO_MANIFEST_OUT="$("$RESOLVE" --root "$LAYOUTS/repo_skills" --skill demo 2>/dev/null)" || true
check "no_manifest_reports_no_host" \
  json_has "$NO_MANIFEST_OUT" "data['skills'][0]['plugin_host'] is None"

# Ignored paths hold local-only fixtures rather than shipped skills, so a walk
# rooted at a repository toplevel drops them. This suite's own scratch tree is
# the case that matters: it carries a SKILL.md per staged scenario, and without
# the filter a whole-repo walk of this repository would return every one of
# them beside the shipped set.
SELF_ALL_OUT="$("$RESOLVE" --root "$REPO_ROOT" --all 2>/dev/null)" || true
check "toplevel_walk_excludes_ignored_scratch_fixtures" \
  json_has "$SELF_ALL_OUT" \
  "not any('/scratch/' in s['path'] or s['path'].startswith('tests/') \
   for s in data['skills'])"
check "toplevel_walk_returns_the_shipped_plugin_skills" \
  json_has "$SELF_ALL_OUT" \
  "data['count'] > 1 and all(s['layout'] == 'plugin' for s in data['skills'])"
# The mirror case: rooted at a directory that merely sits inside another
# repository, a containing repo's ignore rules must not empty the walk. Every
# staged fixture above lives under this repository's own ignored tests/ tree,
# so a filter applied there would drop all of them.
check "nested_root_walk_keeps_its_own_skills" \
  json_has "$SKIPDIRS_OUT" "data.get('count') == 1"

# --- discovery_safety: risky sibling description outlier ------------------
# Every sibling assertion below runs inside one declared comparison group.
# `good_a`, `good_b`, `risky`, `typo_em` and `typo_ell` share no name prefix,
# so a hub `<family>` block is what binds them, and each run passes `--root`
# at the staged tree so the walk reaches that hub. Without the declaration the
# names split by leading segment and `risky` becomes a group of one, which is
# the whole point of the grouping: a finding about siblings needs siblings.

SIBGROUP="$SCRATCH/sibling_group"
DISC_DIR="$SIBGROUP/plugins/demo/skills"
rm -rf "${SCRATCH:?}/sibling_group"

GOOD_A_DESC="Audit alpha widgets for correctness and readiness. Use when checking alpha widgets, widget metadata, or alpha readiness."
GOOD_B_DESC="Audit beta gizmos for packaging and registration. Use when checking beta gizmos, gizmo manifests, or beta registration."
TYPO_EM_DESC="Audit widgets for correctness — and readiness. Use when checking widgets or widget manifests."
TYPO_ELL_DESC="Audit widgets for correctness… and readiness. Use when checking widgets or widget manifests."

write_manifest "$SIBGROUP/plugins/demo" demo
write_skill "$DISC_DIR/sibs" "sibs" \
  "Hub binding the sibling-comparison fixtures into one declared family. Use when testing sibling comparison grouping." \
  "<sibs>
<family>
- \`good_a\` — declared member
- \`good_b\` — declared member
- \`risky\` — declared member
- \`typo_em\` — declared member
- \`typo_ell\` — declared member
</family>
</sibs>"
write_skill "$DISC_DIR/good_a" "good_a" "$GOOD_A_DESC"
write_skill "$DISC_DIR/good_b" "good_b" "$GOOD_B_DESC"
write_skill "$DISC_DIR/typo_em" "typo_em" "$TYPO_EM_DESC"
write_skill "$DISC_DIR/typo_ell" "typo_ell" "$TYPO_ELL_DESC"
# Risky: typographic em dash + hash + tab-ish via explicit risky punct, plus
# workflow leak and missing clear purpose / keyword dump shape.
mkdir -p "$DISC_DIR/risky"
cat > "$DISC_DIR/risky/SKILL.md" <<'EOF'
---
name: risky
description: widgets#gizmos — Step 1 open the file and then invoke the rewriter; Use when widgets, gizmos, widgets, gizmos, widgets, gizmos, widgets, gizmos
version: 1.0.0
author: Test
license: MIT
---

# risky

<body>Risky fixture.</body>
EOF

# The declaration binds every member into one group, and the hub itself stays
# out of the passed set so the message counts only the descriptions measured.
SIBS_GROUP="sibs family"
GROUP_JSON="$("$DISCOVERY" --root "$SIBGROUP" \
  "$DISC_DIR/good_a/SKILL.md" \
  "$DISC_DIR/good_b/SKILL.md" \
  "$DISC_DIR/risky/SKILL.md" \
  "$DISC_DIR/typo_em/SKILL.md" \
  "$DISC_DIR/typo_ell/SKILL.md" 2>/dev/null)" || true
check "sibling_group_binds_every_declared_member" \
  json_has "$GROUP_JSON" \
  "data.get('comparison_groups') == \
   {'$SIBS_GROUP': ['good_a', 'good_b', 'risky', 'typo_ell', 'typo_em']}"

DISC_JSON="$("$DISCOVERY" --root "$SIBGROUP" \
  "$DISC_DIR/good_a/SKILL.md" \
  "$DISC_DIR/good_b/SKILL.md" \
  "$DISC_DIR/risky/SKILL.md" 2>/dev/null)" || disc_rc=$?
disc_rc=${disc_rc:-0}

# Typographic punctuation, workflow leakage, and risky punctuation are quality
# judgements, so they warn. Only a mechanical fault blocks (see the module
# docstring's severity line).
check "discovery_risky_outlier_exits_zero" test "$disc_rc" -eq 0
check "discovery_warns_typographic_punctuation" \
  json_has "$DISC_JSON" \
  "any(i.get('code') == 'description_typographic_punctuation' for i in data.get('warnings', []))"
check "discovery_typographic_punctuation_never_blocks" \
  json_has "$DISC_JSON" \
  "not any('typographic' in i.get('code', '') for i in data.get('blocking', []))"
check "discovery_flags_workflow_leak" \
  json_has "$DISC_JSON" \
  "any(i.get('code') == 'description_workflow_leak' for i in data.get('warnings', []))"
check "discovery_flags_risky_punct_warning" \
  json_has "$DISC_JSON" \
  "any(i.get('code') in ('description_risky_punctuation', 'sibling_risky_punctuation_outlier') for i in data.get('warnings', []))"
check "discovery_names_risky_skill" \
  json_has "$DISC_JSON" \
  "any(i.get('skill') == 'risky' for i in data.get('warnings', []))"
# The em dash belongs to one sibling out of three, so it is a real outlier.
check "discovery_typographic_punctuation_outlier_is_scoped" \
  json_has "$DISC_JSON" \
  "{i['skill'] for i in data['warnings'] if i.get('code') == 'sibling_typographic_punctuation_outlier'} == {'risky'}"
# A remedy-free warning invites a transliteration, so the message names the
# real fix (split the sentence) and rules out the hyphen substitutions a
# reader reaches for instead.
PER_SKILL_TYPO="[i['message'] for i in data['warnings'] if i.get('code') == 'description_typographic_punctuation']"
SIBLING_TYPO="[i['message'] for i in data['warnings'] if i.get('code') == 'sibling_typographic_punctuation_outlier']"
check "discovery_typographic_punctuation_message_names_the_rewrite_remedy" \
  json_has "$DISC_JSON" \
  "all('split the description into two sentences' in m for m in $PER_SKILL_TYPO)"
check "discovery_typographic_punctuation_message_rules_out_hyphen_substitution" \
  json_has "$DISC_JSON" \
  "all('double hyphen' in m and 'en dash' in m for m in $PER_SKILL_TYPO)"
# The UTF-8 half of the old message warned about a failure that cannot occur:
# JSON is UTF-8 by specification and YAML 1.2 is UTF-8 or UTF-16, so every
# consuming manifest and router already reads it. Its removal is the finding.
check "discovery_typographic_punctuation_message_drops_the_utf8_claim" \
  json_has "$DISC_JSON" "not any('UTF-8' in m for m in $PER_SKILL_TYPO)"
check "discovery_sibling_typographic_punctuation_message_names_the_rewrite_remedy" \
  json_has "$DISC_JSON" \
  "all('split the description into two sentences' in m and 'double hyphen' in m \
   and 'en dash' in m for m in $SIBLING_TYPO)"
check "discovery_sibling_typographic_punctuation_message_drops_the_utf8_claim" \
  json_has "$DISC_JSON" "not any('UTF-8' in m for m in $SIBLING_TYPO)"
# Both findings stay judgements about description quality, so both stay at
# warning severity per the SKILL.md severity line.
check "discovery_typographic_punctuation_findings_are_warning_severity" \
  json_has "$DISC_JSON" \
  "all(i.get('severity') == 'warning' for i in data['warnings'] \
   if 'typographic' in i.get('code', ''))"

# --- discovery_safety: typographic punctuation, narrowed from the ASCII axis
# The old check fired on any codepoint above 127, which swept in an accented
# Latin letter and handed it em-dash advice. The narrowed set covers the
# marks that stand in for sentence structure and nothing else.

TYPO="$SCRATCH/typographic"
rm -rf "${SCRATCH:?}/typographic"

# One directory per character, so a regression that drops a single codepoint
# from the set names which one it dropped.
typo_case() {
  mkdir -p "$TYPO/$1"
  write_skill "$TYPO/$1" "$1" "$2"
}
# typo_em and typo_ell reuse the group tree's own descriptions, so the
# single-glyph run and the declared-group run measure the same text.
typo_case "typo_em"  "$TYPO_EM_DESC"
typo_case "typo_en"  "Audit widgets for correctness – and readiness. Use when checking widgets or widget manifests."
typo_case "typo_lsq" "Audit ‘widget' correctness and readiness. Use when checking widgets or widget manifests."
typo_case "typo_rsq" "Audit the widget’s correctness and readiness. Use when checking widgets or widget manifests."
# shellcheck disable=SC1111  # the curly quote is the fixture under test
typo_case "typo_ldq" "Audit “widget correctness\" and readiness. Use when checking widgets or widget manifests."
# shellcheck disable=SC1111  # the curly quote is the fixture under test
typo_case "typo_rdq" "Audit widget correctness” and readiness. Use when checking widgets or widget manifests."
typo_case "typo_ell" "$TYPO_ELL_DESC"

for glyph in typo_em typo_en typo_lsq typo_rsq typo_ldq typo_rdq typo_ell; do
  GLYPH_JSON="$("$DISCOVERY" "$TYPO/$glyph/SKILL.md" 2>/dev/null)" || true
  check "typographic_fires_on_$glyph" \
    json_has "$GLYPH_JSON" \
    "any(i.get('code') == 'description_typographic_punctuation' for i in data.get('warnings', []))"
done

# The case the ASCII boundary got wrong: accented Latin letters carry no
# clause break, so neither finding has anything to say about them.
mkdir -p "$TYPO/accented_a" "$TYPO/accented_b"
write_skill "$TYPO/accented_a" "accented_a" \
  "Audit café and résumé widgets for correctness. Use when checking accented widgets or widget manifests."
write_skill "$TYPO/accented_b" "accented_b" \
  "Audit Gödel gizmos for packaging and registration. Use when checking gizmo manifests or registration."
ACCENT_JSON="$("$DISCOVERY" --root "$TYPO" \
  "$TYPO/accented_a/SKILL.md" "$TYPO/accented_b/SKILL.md" 2>/dev/null)" \
  && accent_rc=0 || accent_rc=$?
check "typographic_stays_silent_on_accented_letters" \
  json_has "$ACCENT_JSON" \
  "not any('typographic' in i.get('code', '') for i in data.get('warnings', []) + data.get('blocking', []))"
check "typographic_accented_letters_exit_zero" test "${accent_rc:-0}" -eq 0

# A set carrying none of these characters draws no sibling finding, unchanged
# from the outlier helper's own proper-subset rule.
CLEAN_SET_JSON="$("$DISCOVERY" --root "$SIBGROUP" \
  "$DISC_DIR/good_a/SKILL.md" "$DISC_DIR/good_b/SKILL.md" 2>/dev/null)" || true
check "typographic_clean_set_draws_no_sibling_finding" \
  json_has "$CLEAN_SET_JSON" \
  "not any(i.get('code') == 'sibling_typographic_punctuation_outlier' for i in data.get('warnings', []))"

# The message reports the split the run measured. Two carriers out of four is
# the case the old text got wrong: it told each carrier its siblings were
# clean while another carrier sat in the same set. All four sit in the one
# declared group, where two `typo_` carriers alone would have filled their own
# prefix set and left `is_outlier_trait` with nothing to call an outlier.
MULTI_JSON="$("$DISCOVERY" --root "$SIBGROUP" \
  "$DISC_DIR/typo_em/SKILL.md" "$DISC_DIR/typo_ell/SKILL.md" \
  "$DISC_DIR/good_a/SKILL.md" "$DISC_DIR/good_b/SKILL.md" 2>/dev/null)" || true
MULTI_MSGS="[i['message'] for i in data['warnings'] if i.get('code') == 'sibling_typographic_punctuation_outlier']"
check "typographic_multi_carrier_finding_covers_every_carrier" \
  json_has "$MULTI_JSON" \
  "{i['skill'] for i in data['warnings'] if i.get('code') == 'sibling_typographic_punctuation_outlier'} \
   == {'typo_em', 'typo_ell'}"
check "typographic_multi_carrier_message_states_the_count" \
  json_has "$MULTI_JSON" "all('2 of 4 descriptions' in m for m in $MULTI_MSGS)"
check "typographic_multi_carrier_message_names_the_carriers" \
  json_has "$MULTI_JSON" \
  "all('typo_ell' in m and 'typo_em' in m for m in $MULTI_MSGS)"
check "typographic_multi_carrier_message_claims_no_clean_siblings" \
  json_has "$MULTI_JSON" "not any('siblings stay ASCII-only' in m for m in $MULTI_MSGS)"

# One carrier is the same wording with a count of one, so the single-carrier
# case needs no separate sentence.
SINGLE_MSGS="[i['message'] for i in data['warnings'] if i.get('code') == 'sibling_typographic_punctuation_outlier']"
check "typographic_single_carrier_still_finds_the_outlier" \
  json_has "$DISC_JSON" \
  "all('1 of 3 descriptions' in m for m in $SINGLE_MSGS)"
check "typographic_single_carrier_message_names_that_sibling" \
  json_has "$DISC_JSON" "all('risky' in m for m in $SINGLE_MSGS)"
# The message reports the group it measured, so a reader can tell which
# siblings the count is over.
check "typographic_message_names_the_comparison_group" \
  json_has "$DISC_JSON" "all('in the $SIBS_GROUP' in m for m in $SINGLE_MSGS)"

# --- discovery_safety: the group a sibling comparison runs inside ----------
# Every sibling finding says the description is out of step with its
# *siblings*, which the flat comparison never established: it measured
# whatever paths the run passed. The comparison group is now derived from the
# given names — each name's family-name token resolved against the walk at
# --root, with a same-prefix member another plugin hosts split into its own
# group unless the hub's <family> block names it. Each scenario below pins one
# reading of that rule, and each contamination case also shows the finding the
# flat comparison used to produce, so an absence is the grouping rather than a
# fixture too weak to fire.

# Not GROUPS: bash owns that name for the caller's group ids and documents
# that assignments to it have no effect, so the fixture root would silently
# become a relative path and stage every fixture into the working tree.
GROUPDIR="$SCRATCH/comparison_groups"
rm -rf "${SCRATCH:?}/comparison_groups"

# Two descriptions built to trip the pairwise routing-overlap check against
# each other while keeping their purpose clauses distinct; the blocking
# identical-purpose reading gets its own scenario below.
OVERLAP_ONE="Audit widget manifests for packaging drift across the widget tree. Use when checking widget manifests, widget packaging, or widget tree drift."
OVERLAP_TWO="Audit widget packaging for manifest drift across the widget tree. Use when checking widget packaging, widget manifests, or widget tree drift."

# The pre-change comparison. Labelling every report with one group is exactly
# what the script measured before it derived a grouping, so these two helpers
# report what the flat set produced on the same fixtures.
flat_sibling_pairs() {
  SD_DISC="$DISCOVERY" python3 - "$@" <<'PY'
import importlib.util, os, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("ds", os.environ["SD_DISC"])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
reports = [mod.analyze_skill(Path(p)) for p in sys.argv[1:]]
flat = {r["path"]: "flat set" for r in reports}
print(sorted((f["code"], f["skill"]) for f in mod.sibling_findings(reports, flat)))
PY
}
flat_has_sibling_code() {
  local expect="$1"
  shift
  flat_sibling_pairs "$@" | grep -qF "'$expect'"
}
# The (code, skill) pairs one run's sibling findings carry, as one sorted line.
sibling_pairs() {
  SKILL_DOCTOR_JSON="$1" python3 -c "
import json, os
data = json.loads(os.environ['SKILL_DOCTOR_JSON'])
print(sorted(
    (i['code'], i['skill'])
    for i in data.get('warnings', []) + data.get('blocking', [])
    if i['code'].startswith('sibling_')
))
"
}
sibling_codes_are() {
  json_has "$1" \
    "sorted({i['code'] for i in data.get('warnings', []) + data.get('blocking', []) \
             if i['code'].startswith('sibling_')}) == $2"
}

# 1. A same-prefix pair hosted by two plugins with no hub is a coincidence
#    rather than a family, so neither member is measured against the other.
#    Membership is untouched: the walk lists both and the family run keeps
#    both and still names the split.
COINCIDE="$GROUPDIR/coincidence"
write_manifest "$COINCIDE/plugins/one" one
write_manifest "$COINCIDE/plugins/two" two
write_skill "$COINCIDE/plugins/one/skills/db_query" "db_query" "$OVERLAP_ONE"
write_skill "$COINCIDE/plugins/two/skills/db_migrate" "db_migrate" "$OVERLAP_TWO"
COINCIDE_PATHS=(
  "$COINCIDE/plugins/one/skills/db_query/SKILL.md"
  "$COINCIDE/plugins/two/skills/db_migrate/SKILL.md"
)
COINCIDE_JSON="$("$DISCOVERY" --root "$COINCIDE" "${COINCIDE_PATHS[@]}" 2>/dev/null)" \
  && coincide_rc=0 || coincide_rc=$?
check "coincidence_pair_draws_no_sibling_finding" \
  sibling_codes_are "$COINCIDE_JSON" "[]"
check "coincidence_pair_splits_into_one_group_per_plugin" \
  json_has "$COINCIDE_JSON" \
  "data.get('comparison_groups') == {'db family (plugins/one)': ['db_query'], \
                                     'db family (plugins/two)': ['db_migrate']}"
check "coincidence_pair_exits_zero" test "${coincide_rc:-0}" -eq 0
check "coincidence_pair_did_fire_in_the_flat_comparison" \
  flat_has_sibling_code sibling_routing_overlap "${COINCIDE_PATHS[@]}"
COINCIDE_ALL="$("$RESOLVE" --root "$COINCIDE" --all 2>/dev/null)" || true
check "coincidence_walk_lists_both_skills" \
  json_has "$COINCIDE_ALL" \
  "set(s['name'] for s in data['skills']) == {'db_query', 'db_migrate'}"
COINCIDE_FAM="$("$RESOLVE" --root "$COINCIDE" --family db 2>/dev/null)" || true
check "coincidence_family_run_keeps_both_members" \
  json_has "$COINCIDE_FAM" \
  "set(s['name'] for s in data['skills']) == {'db_query', 'db_migrate'}"
check "coincidence_family_run_still_warns_on_the_split" \
  has_warning "$COINCIDE_FAM" family_spans_plugins

# 2. The declared reading of the same shape: a hub whose <family> block names
#    the member in the other plugin keeps its sibling coverage across the
#    split, so a genuine cross-plugin family loses nothing.
DECLARED_SPAN="$GROUPDIR/declared_span"
write_manifest "$DECLARED_SPAN/plugins/one" one
write_manifest "$DECLARED_SPAN/plugins/two" two
write_skill "$DECLARED_SPAN/plugins/one/skills/db" "db" \
  "Hub declaring a widget family that spans two plugins. Use when testing a declared cross-plugin family." \
  "<db>
<family>
- \`db_query\` — declared member
- \`db_migrate\` — declared member hosted by the other plugin
</family>
</db>"
write_skill "$DECLARED_SPAN/plugins/one/skills/db_query" "db_query" "$OVERLAP_ONE"
write_skill "$DECLARED_SPAN/plugins/two/skills/db_migrate" "db_migrate" "$OVERLAP_TWO"
DECLARED_SPAN_JSON="$("$DISCOVERY" --root "$DECLARED_SPAN" \
  "$DECLARED_SPAN/plugins/one/skills/db_query/SKILL.md" \
  "$DECLARED_SPAN/plugins/two/skills/db_migrate/SKILL.md" 2>/dev/null)" || true
check "declared_span_compares_across_the_plugin_split" \
  json_has "$DECLARED_SPAN_JSON" \
  "data.get('comparison_groups') == \
   {'db family (plugins/one)': ['db_migrate', 'db_query']}"
check "declared_span_keeps_its_pairwise_finding" \
  sibling_codes_are "$DECLARED_SPAN_JSON" "['sibling_routing_overlap']"

# 3. The common case, unchanged: a hubless prefix family wholly inside one
#    plugin produces exactly the sibling findings the flat comparison did.
HUBLESS="$GROUPDIR/hubless_one_plugin"
write_manifest "$HUBLESS/plugins/one" one
write_skill "$HUBLESS/plugins/one/skills/fmt_alpha" "fmt_alpha" "$GOOD_A_DESC"
write_skill "$HUBLESS/plugins/one/skills/fmt_beta" "fmt_beta" "$GOOD_B_DESC"
write_skill "$HUBLESS/plugins/one/skills/fmt_gamma" "fmt_gamma" "$TYPO_EM_DESC"
HUBLESS_PATHS=(
  "$HUBLESS/plugins/one/skills/fmt_alpha/SKILL.md"
  "$HUBLESS/plugins/one/skills/fmt_beta/SKILL.md"
  "$HUBLESS/plugins/one/skills/fmt_gamma/SKILL.md"
)
HUBLESS_JSON="$("$DISCOVERY" --root "$HUBLESS" "${HUBLESS_PATHS[@]}" 2>/dev/null)" || true
check "hubless_one_plugin_family_is_one_group" \
  json_has "$HUBLESS_JSON" \
  "data.get('comparison_groups') == \
   {'fmt family': ['fmt_alpha', 'fmt_beta', 'fmt_gamma']}"
check "hubless_one_plugin_family_findings_are_unchanged" \
  test "$(sibling_pairs "$HUBLESS_JSON")" = "$(flat_sibling_pairs "${HUBLESS_PATHS[@]}")"
# The equality above is only worth something when the family produces a
# sibling finding at all, so name the one the em-dash member earns. A routing
# overlap between two members rides along and is equally present either side.
check "hubless_one_plugin_family_still_finds_its_outlier" \
  json_has "$HUBLESS_JSON" \
  "{i['skill'] for i in data['warnings'] \
    if i['code'] == 'sibling_typographic_punctuation_outlier'} == {'fmt_gamma'}"
# No hub is required for that resolution, and the family selector agrees.
HUBLESS_FAM="$("$RESOLVE" --root "$HUBLESS" --family fmt 2>/dev/null)" || true
check "hubless_prefix_family_resolves_without_a_hub" \
  json_has "$HUBLESS_FAM" \
  "set(s['name'] for s in data['skills']) == \
   {'fmt_alpha', 'fmt_beta', 'fmt_gamma'} \
   and 'fmt' not in set(s['name'] for s in data['skills'])"

# 4. Correctness needs no grouping argument from the caller: paths from two
#    families, nothing but --root, and they group by their own names. The
#    second run proves a given path the walk never lists still classifies —
#    rooted at this repository, whose walk drops the gitignored tests/ tree.
TWOFAM="$GROUPDIR/two_families"
write_manifest "$TWOFAM/plugins/one" one
write_skill "$TWOFAM/plugins/one/skills/alpha_reader" "alpha_reader" "$OVERLAP_ONE"
write_skill "$TWOFAM/plugins/one/skills/beta_writer" "beta_writer" "$OVERLAP_TWO"
TWOFAM_PATHS=(
  "$TWOFAM/plugins/one/skills/alpha_reader/SKILL.md"
  "$TWOFAM/plugins/one/skills/beta_writer/SKILL.md"
)
TWOFAM_GROUPS="{'alpha family': ['alpha_reader'], 'beta family': ['beta_writer']}"
TWOFAM_JSON="$("$DISCOVERY" --root "$TWOFAM" "${TWOFAM_PATHS[@]}" 2>/dev/null)" || true
check "two_families_group_with_no_grouping_argument" \
  json_has "$TWOFAM_JSON" "data.get('comparison_groups') == $TWOFAM_GROUPS"
check "two_families_draw_no_cross_family_finding" \
  sibling_codes_are "$TWOFAM_JSON" "[]"
check "two_families_did_fire_in_the_flat_comparison" \
  flat_has_sibling_code sibling_routing_overlap "${TWOFAM_PATHS[@]}"
OMITTED_JSON="$("$DISCOVERY" --root "$REPO_ROOT" "${TWOFAM_PATHS[@]}" 2>/dev/null)" || true
check "walk_omitted_paths_still_classify" \
  json_has "$OMITTED_JSON" "data.get('comparison_groups') == $TWOFAM_GROUPS"
check "walk_omitted_paths_draw_no_cross_family_finding" \
  sibling_codes_are "$OMITTED_JSON" "[]"
check "repo_walk_omits_the_gitignored_staged_paths" \
  json_has "$("$RESOLVE" --root "$REPO_ROOT" --all 2>/dev/null)" \
  "'alpha_reader' not in set(s['name'] for s in data['skills'])"
SOLO_GROUP_JSON="$("$DISCOVERY" --root "$TWOFAM" "${TWOFAM_PATHS[0]}" 2>/dev/null)" || true
check "single_skill_run_draws_no_sibling_finding" \
  sibling_codes_are "$SOLO_GROUP_JSON" "[]"

# 5. The blocking sibling finding, in both readings. Identical purpose
#    summaries between strangers who merely share a name prefix across two
#    plugins gate nothing; between declared siblings the block stays.
IDENT_PURPOSE="Manage the project widget backlog as plain markdown files in widgets."
IDENT_ONE="$IDENT_PURPOSE Use when the user asks about widget backlog work or widget files."
IDENT_TWO="$IDENT_PURPOSE Use when the user wants widget items listed, triaged, or archived."

IDENT_SPLIT="$GROUPDIR/identical_purpose_split"
write_manifest "$IDENT_SPLIT/plugins/one" one
write_manifest "$IDENT_SPLIT/plugins/two" two
write_skill "$IDENT_SPLIT/plugins/one/skills/wg_one" "wg_one" "$IDENT_ONE"
write_skill "$IDENT_SPLIT/plugins/two/skills/wg_two" "wg_two" "$IDENT_TWO"
IDENT_SPLIT_PATHS=(
  "$IDENT_SPLIT/plugins/one/skills/wg_one/SKILL.md"
  "$IDENT_SPLIT/plugins/two/skills/wg_two/SKILL.md"
)
IDENT_SPLIT_JSON="$("$DISCOVERY" --root "$IDENT_SPLIT" \
  "${IDENT_SPLIT_PATHS[@]}" 2>/dev/null)" && ident_split_rc=0 || ident_split_rc=$?
check "identical_purpose_across_plugins_does_not_block" \
  json_has "$IDENT_SPLIT_JSON" \
  "not any(i.get('code') == 'sibling_purpose_not_distinct' \
           for i in data.get('blocking', []))"
check "identical_purpose_across_plugins_exits_zero" \
  test "${ident_split_rc:-0}" -eq 0
check "identical_purpose_across_plugins_blocked_in_the_flat_comparison" \
  flat_has_sibling_code sibling_purpose_not_distinct "${IDENT_SPLIT_PATHS[@]}"

IDENT_DECL="$GROUPDIR/identical_purpose_declared"
write_manifest "$IDENT_DECL/plugins/one" one
write_skill "$IDENT_DECL/plugins/one/skills/wg" "wg" \
  "Hub declaring the identical-purpose sibling pair. Use when testing declared sibling purpose distinctness." \
  "<wg>
<family>
- \`wg_one\` — declared member
- \`wg_two\` — declared member
</family>
</wg>"
write_skill "$IDENT_DECL/plugins/one/skills/wg_one" "wg_one" "$IDENT_ONE"
write_skill "$IDENT_DECL/plugins/one/skills/wg_two" "wg_two" "$IDENT_TWO"
IDENT_DECL_JSON="$("$DISCOVERY" --root "$IDENT_DECL" \
  "$IDENT_DECL/plugins/one/skills/wg_one/SKILL.md" \
  "$IDENT_DECL/plugins/one/skills/wg_two/SKILL.md" 2>/dev/null)" \
  && ident_decl_rc=0 || ident_decl_rc=$?
check "identical_purpose_between_declared_siblings_blocks" \
  json_has "$IDENT_DECL_JSON" \
  "any(i.get('code') == 'sibling_purpose_not_distinct' \
       for i in data.get('blocking', []))"
check "identical_purpose_between_declared_siblings_exits_nonzero" \
  test "${ident_decl_rc:-0}" -ne 0

# 6. A whole-repo set of skills that belong to no family: each is a group of
#    one, so no sibling finding names any of them, while every per-skill
#    finding they carry stays exactly as it was.
LONERS="$GROUPDIR/unaffiliated"
write_manifest "$LONERS/plugins/one" one
write_skill "$LONERS/plugins/one/skills/kettle" "kettle" "$TYPO_EM_DESC"
write_skill "$LONERS/plugins/one/skills/lantern" "lantern" "$GOOD_A_DESC"
write_skill "$LONERS/plugins/one/skills/mallet" "mallet" "$GOOD_B_DESC"
LONERS_PATHS=(
  "$LONERS/plugins/one/skills/kettle/SKILL.md"
  "$LONERS/plugins/one/skills/lantern/SKILL.md"
  "$LONERS/plugins/one/skills/mallet/SKILL.md"
)
check "unaffiliated_fixture_is_the_whole_repo_set" \
  json_has "$("$RESOLVE" --root "$LONERS" --all 2>/dev/null)" \
  "set(s['name'] for s in data['skills']) == {'kettle', 'lantern', 'mallet'}"
LONERS_JSON="$("$DISCOVERY" --root "$LONERS" "${LONERS_PATHS[@]}" 2>/dev/null)" || true
check "unaffiliated_skills_are_groups_of_one" \
  json_has "$LONERS_JSON" \
  "data.get('comparison_groups') == {'kettle family': ['kettle'], \
                                     'lantern family': ['lantern'], \
                                     'mallet family': ['mallet']}"
check "unaffiliated_set_draws_no_sibling_finding" \
  sibling_codes_are "$LONERS_JSON" "[]"
check "unaffiliated_skills_keep_their_per_skill_findings" \
  json_has "$LONERS_JSON" \
  "{i['skill'] for i in data['warnings'] \
    if i['code'] == 'description_typographic_punctuation'} == {'kettle'}"
check "unaffiliated_set_was_contaminated_in_the_flat_comparison" \
  flat_has_sibling_code sibling_typographic_punctuation_outlier "${LONERS_PATHS[@]}"

# 7. This repository's own whole-repo run. Every sibling finding has to name
#    its group and name only members of it, and every group has to hold one
#    family — which is the claim each finding's message makes and the flat
#    comparison never established.
SELF_ALL_PATHS=()
while IFS= read -r rel; do
  SELF_ALL_PATHS+=("$REPO_ROOT/$rel")
done < <("$RESOLVE" --root "$REPO_ROOT" --all 2>/dev/null | python3 -c "
import json, sys
for skill in json.load(sys.stdin)['skills']:
    print(skill['path'])
")
SELF_DISC_JSON="$("$DISCOVERY" --root "$REPO_ROOT" "${SELF_ALL_PATHS[@]}" 2>/dev/null)" \
  && self_disc_rc=0 || self_disc_rc=$?
check "self_whole_repo_run_exits_zero" test "${self_disc_rc:-0}" -eq 0
check "self_whole_repo_sibling_findings_name_their_own_group" \
  json_has "$SELF_DISC_JSON" \
  "all(i.get('group') in data['comparison_groups'] \
       and all(n in data['comparison_groups'][i['group']] \
               for n in i['skill'].split(' vs ')) \
       for i in data.get('warnings', []) + data.get('blocking', []) \
       if i['code'].startswith('sibling_'))"
check "self_whole_repo_groups_each_hold_one_family" \
  json_has "$SELF_DISC_JSON" \
  "all(all(n == label.split(' ')[0] or n.startswith(label.split(' ')[0] + '_') \
           for n in names) \
       for label, names in data['comparison_groups'].items())"

# --- the shared discovery module ------------------------------------------
# One implementation of the walk, the frontmatter name read, the plugin-host
# lookup and the <family> parse, so the two scripts cannot drift apart. Both
# load paths in use have to reach it: a script run by absolute path, and the
# importlib.util.spec_from_file_location form this suite uses.

SHARED="$SKILL_DIR/scripts/skill_discovery.py"
check "shared_discovery_module_exists" test -f "$SHARED"
check "shared_module_defines_split_frontmatter_and_skill_file_re" \
  grep -Eq '^def split_frontmatter' "$SHARED" \
  && grep -Eq '^SKILL_FILE_RE = ' "$SHARED"
check "neither_script_redefines_split_frontmatter" \
  bash -c "! grep -Eq '^def split_frontmatter' \"$RESOLVE\"" \
  && bash -c "! grep -Eq '^def split_frontmatter' \"$DISCOVERY\""
check "neither_script_redefines_skill_file_re" \
  bash -c "! grep -Eq '^SKILL_FILE_RE = ' \"$RESOLVE\"" \
  && bash -c "! grep -Eq '^SKILL_FILE_RE = ' \"$DISCOVERY\""
check "scripts_run_by_absolute_path_load_the_shared_module" \
  bash -c "\"$RESOLVE\" --root \"$SIBGROUP\" --all >/dev/null 2>&1" \
  && bash -c "\"$DISCOVERY\" --root \"$SIBGROUP\" \"$DISC_DIR/good_a/SKILL.md\" >/dev/null 2>&1"

IMPORTLIB_OUT="$(SD_RESOLVE="$RESOLVE" SD_DISC="$DISCOVERY" python3 - <<'PY'
import importlib.util, os


def load(label, path):
    spec = importlib.util.spec_from_file_location(label, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


rs = load("resolve_scope", os.environ["SD_RESOLVE"])
ds = load("discovery_safety", os.environ["SD_DISC"])
print("resolve-reexports:", all(
    hasattr(rs, name)
    for name in (
        "parse_family_block_names", "split_frontmatter", "SKILL_FILE_RE",
        "discover_skills", "read_frontmatter_name", "find_plugin_host",
        "resolve_family_set", "shares_family_name",
    )
))
print("discovery-imports:", all(
    hasattr(ds, name)
    for name in ("split_frontmatter", "SKILL_FILE_RE", "comparison_groups")
))
print("one-implementation:", (
    rs.split_frontmatter is ds.split_frontmatter
    and rs.SKILL_FILE_RE is ds.SKILL_FILE_RE
))
PY
)"
check "importlib_load_keeps_the_resolve_scope_reexports" \
  err_has "$IMPORTLIB_OUT" "resolve-reexports: True"
check "importlib_load_reaches_the_discovery_imports" \
  err_has "$IMPORTLIB_OUT" "discovery-imports: True"
check "both_scripts_share_one_implementation" \
  err_has "$IMPORTLIB_OUT" "one-implementation: True"

# --- Static contract: the group rule is stated once -----------------------

sibling_findings_docstring() {
  SD_SRC="$DISCOVERY" python3 -c "
import ast, os, sys
tree = ast.parse(open(os.environ['SD_SRC'], encoding='utf-8').read())
node = next((n for n in tree.body
             if isinstance(n, ast.FunctionDef) and n.name == 'sibling_findings'),
            None)
doc = ast.get_docstring(node) if node else ''
sys.exit(0 if doc and 'comparison group' in doc and 'selected set' not in doc else 1)
"
}
check "no_selected_set_phrase_survives" \
  bash -c "! grep -qF 'selected set' \"$SKILL_MD\"" \
  && bash -c "! grep -qF 'selected set' \"$DISCOVERY\""
check "discovery_safety_states_the_comparison_group_rule" \
  section_has discovery_safety \
    "measures one description against the skills a deliberate declaration binds it to" \
  && section_has discovery_safety "derives that comparison group itself from the walk under" \
  && section_has discovery_safety "splits a same-prefix member another plugin hosts into its own group"
check "discovery_safety_states_the_group_of_one_consequence" \
  section_has discovery_safety "is a group of one and draws no sibling finding"
check "sibling_findings_docstring_agrees_with_the_group_rule" \
  sibling_findings_docstring

# --- discovery_safety: listing-budget description length ------------------
# A description long enough to lose its listing entry is a property of the one
# file, so the finding runs per skill: sibling_length_outlier returns early on
# a single target and compares against a mean on a set, which leaves the
# absolute risk unmeasured in both cases.

BUDGET="$SCRATCH/listing_budget"
rm -rf "${SCRATCH:?}/listing_budget"

write_skill_desc_len "$BUDGET/solo/long_solo" "long_solo" 1200
SOLO_JSON="$("$DISCOVERY" "$BUDGET/solo/long_solo/SKILL.md" 2>/dev/null)" \
  && solo_rc=0 || solo_rc=$?
BUDGET_CODE="description_listing_budget_length"
BUDGET_MSGS="[i['message'] for i in data['warnings'] if i.get('code') == '$BUDGET_CODE']"

check "budget_solo_finding_without_siblings" \
  json_has "$SOLO_JSON" \
  "any(i.get('code') == '$BUDGET_CODE' for i in data.get('warnings', []))"
check "budget_solo_finding_is_warning_severity" \
  json_has "$SOLO_JSON" \
  "all(i.get('severity') == 'warning' for i in data['warnings'] if i.get('code') == '$BUDGET_CODE')"
check "budget_solo_finding_never_blocks" \
  json_has "$SOLO_JSON" \
  "not any(i.get('code') == '$BUDGET_CODE' for i in data.get('blocking', []))"
check "budget_solo_exits_zero" test "${solo_rc:-0}" -eq 0
# The message is the whole deliverable for a reader who sees a bare listing
# entry, so it has to carry the arithmetic rather than just the verdict.
check "budget_message_states_measured_length" \
  json_has "$SOLO_JSON" "all('1200 characters' in m for m in $BUDGET_MSGS)"
check "budget_message_states_threshold" \
  json_has "$SOLO_JSON" "all('1000-character threshold' in m for m in $BUDGET_MSGS)"
check "budget_message_names_the_budget" \
  json_has "$SOLO_JSON" "all('budget' in m for m in $BUDGET_MSGS)"
check "budget_message_explains_the_usage_ranking" \
  json_has "$SOLO_JSON" \
  "all('recency-weighted usage ranking' in m and 'never-invoked' in m for m in $BUDGET_MSGS)"

# A whole set over the threshold, with lengths too close for the sibling
# comparison to call any of them an outlier. Every member is at risk, so every
# member gets the finding.
write_skill_desc_len "$BUDGET/set/long_a" "long_a" 1100
write_skill_desc_len "$BUDGET/set/long_b" "long_b" 1140
write_skill_desc_len "$BUDGET/set/long_c" "long_c" 1180
SET_JSON="$("$DISCOVERY" --root "$BUDGET/set" \
  "$BUDGET/set/long_a/SKILL.md" \
  "$BUDGET/set/long_b/SKILL.md" \
  "$BUDGET/set/long_c/SKILL.md" 2>/dev/null)" || true
check "budget_set_finding_for_every_member" \
  json_has "$SET_JSON" \
  "{i['skill'] for i in data['warnings'] if i.get('code') == '$BUDGET_CODE'} == {'long_a', 'long_b', 'long_c'}"
check "budget_set_sibling_outlier_stays_quiet" \
  json_has "$SET_JSON" \
  "not any(i.get('code') == 'sibling_length_outlier' for i in data.get('warnings', []))"

# The recorded incident: five sibling descriptions of 1047, 887, 781, 624, and
# 591 characters, where the 1047 entry is the one the harness actually listed
# by name alone. The sibling comparison misses it (mean near 786 puts its
# threshold near 590), which is why the absolute check exists.
for pair in recorded_1047:1047 recorded_887:887 recorded_781:781 \
            recorded_624:624 recorded_591:591; do
  write_skill_desc_len "$BUDGET/recorded/${pair%%:*}" "${pair%%:*}" "${pair##*:}"
done
REC_JSON="$("$DISCOVERY" --root "$BUDGET/recorded" \
  "$BUDGET/recorded/recorded_1047/SKILL.md" \
  "$BUDGET/recorded/recorded_887/SKILL.md" \
  "$BUDGET/recorded/recorded_781/SKILL.md" \
  "$BUDGET/recorded/recorded_624/SKILL.md" \
  "$BUDGET/recorded/recorded_591/SKILL.md" 2>/dev/null)" || true
check "budget_recorded_set_flags_the_dropped_entry" \
  json_has "$REC_JSON" \
  "{i['skill'] for i in data['warnings'] if i.get('code') == '$BUDGET_CODE'} == {'recorded_1047'}"
check "budget_recorded_set_sibling_outlier_misses_it" \
  json_has "$REC_JSON" \
  "not any(i.get('code') == 'sibling_length_outlier' for i in data.get('warnings', []))"

# A description well under the threshold draws no finding.
write_skill_desc_len "$BUDGET/short/short_solo" "short_solo" 300
SHORT_JSON="$("$DISCOVERY" "$BUDGET/short/short_solo/SKILL.md" 2>/dev/null)" || true
check "budget_short_description_draws_no_finding" \
  json_has "$SHORT_JSON" \
  "not any(i.get('code') == '$BUDGET_CODE' for i in data.get('warnings', []) + data.get('blocking', []))"

# The sibling comparison keeps its own job: one description far off its
# family's mean, all of them under the budget threshold. Same code, same
# warning severity as before the absolute check landed.
write_skill_desc_len "$BUDGET/outlier/spread_long" "spread_long" 700
write_skill_desc_len "$BUDGET/outlier/spread_a" "spread_a" 130
write_skill_desc_len "$BUDGET/outlier/spread_b" "spread_b" 130
OUTLIER_JSON="$("$DISCOVERY" --root "$BUDGET/outlier" \
  "$BUDGET/outlier/spread_long/SKILL.md" \
  "$BUDGET/outlier/spread_a/SKILL.md" \
  "$BUDGET/outlier/spread_b/SKILL.md" 2>/dev/null)" || true
check "budget_sibling_outlier_still_fires_unchanged" \
  json_has "$OUTLIER_JSON" \
  "{(i['skill'], i.get('severity')) for i in data['warnings'] if i.get('code') == 'sibling_length_outlier'} == {('spread_long', 'warning')}"
check "budget_sibling_outlier_set_draws_no_budget_finding" \
  json_has "$OUTLIER_JSON" \
  "not any(i.get('code') == '$BUDGET_CODE' for i in data.get('warnings', []) + data.get('blocking', []))"

# --- discovery_safety: parser-hostile characters block --------------------

HOSTILE="$SCRATCH/hostile/SKILL.md"
mkdir -p "$(dirname "$HOSTILE")"
# U+200B ZERO WIDTH SPACE between "hostile" and "widgets" — invisible in a
# manifest and a real parse/routing hazard, unlike an em dash.
printf '%s\n' \
  '---' \
  'name: hostile' \
  "description: Audit hostile​widgets for correctness. Use when checking hostile widgets or widget manifests." \
  'version: 1.0.0' \
  'author: Test' \
  'license: MIT' \
  '---' \
  '' \
  '# hostile' > "$HOSTILE"
HOSTILE_JSON="$("$DISCOVERY" "$HOSTILE" 2>/dev/null)" && hostile_rc=0 || hostile_rc=$?
check "discovery_blocks_hostile_char" \
  json_has "$HOSTILE_JSON" \
  "any(i.get('code') == 'description_hostile_characters' for i in data.get('blocking', []))"
check "discovery_hostile_exits_nonzero" test "${hostile_rc:-0}" -ne 0

# --- discovery_safety: no false blocks on real shipped descriptions -------
# Regression guard. A closed purpose-verb list and a blanket block on every
# codepoint above 127 used to fail healthy shipped skills — an em-dash lead,
# an "Import ..." purpose verb, and a crisp sub-40-character purpose sentence
# all blocked.

REAL="$SCRATCH/real_shapes/skills"
rm -rf "${SCRATCH:?}/real_shapes"
mkdir -p "$REAL/em_dash_lead" "$REAL/import_verb" "$REAL/short_purpose" \
  "$REAL/coverage_tail" "$REAL/noun_only" "$REAL/file_type_only"
write_skill "$REAL/em_dash_lead" "em_dash_lead" \
  "Check-only doctor for skill artifacts — audits SKILL.md frontmatter and descriptions, registration, and tests. Use when checking a skill or auditing SKILL.md metadata."
write_skill "$REAL/import_verb" "import_verb" \
  "Import a single external resource (URL, file, paper, PDF, transcript, paste) into the wiki with a user-reviewable triage step before any wiki page is written. Use when the user asks to ingest or import a source."
write_skill "$REAL/short_purpose" "short_purpose" \
  "Close one completed or parked task. Use when the user asks to finish, mark done, defer, park, drop, or archive a task."
write_skill "$REAL/coverage_tail" "coverage_tail" \
  "Apply formatting standards and best practices when generating or editing Python code (.py). Covers indentation, quoting, imports, naming, line length, type hints, logging, and testing."
# The four shapes above all clear trigger detection through an explicit
# `Use when` / `when ...` clause, so neither of the widened trigger paths
# decides their verdict. These two isolate one path each: plural artefact
# nouns with no trigger clause (the shipped ai_instruction_formatting shape),
# and a bare file type with fewer than three artefact nouns.
write_skill "$REAL/noun_only" "noun_only" \
  "Organize AI-consumed content (prompts, rules, skills, commands, agents, system instructions) into pseudo-XML by wrapping each semantic concern in a dedicated tag for role, policy, inputs, and output contract."
write_skill "$REAL/file_type_only" "file_type_only" \
  "Apply linter-aligned style conventions to Ruby source files (.rb), covering indentation, quoting, naming, and error handling."

DUAL_AUDIENCE_CODES="{'description_missing_purpose', 'description_missing_triggers', 'description_dual_audience_gap'}"

for shape in em_dash_lead import_verb short_purpose coverage_tail \
             noun_only file_type_only; do
  SHAPE_JSON="$("$DISCOVERY" "$REAL/$shape/SKILL.md" 2>/dev/null)" || true
  # Severity guard: restoring a blanket block above codepoint 127 fails this.
  check "real_shape_no_block_$shape" \
    json_has "$SHAPE_JSON" "data.get('blocking_count') == 0"
  # The em-dash lead is the one shape carrying a character in the narrowed
  # set, so it is where the code name is observable on a real shipped shape.
  if [[ "$shape" == "em_dash_lead" ]]; then
    check "real_shape_em_dash_lead_draws_the_typographic_warning" \
      json_has "$SHAPE_JSON" \
      "{i.get('code') for i in data.get('warnings', [])} \
       >= {'description_typographic_punctuation'}"
  fi
  # Heuristic guard, and it has to name the codes. `blocking_count == 0`
  # cannot carry this claim: the severity split means no purpose or trigger
  # heuristic can produce a blocking finding, so a reverted heuristic would
  # emit its finding as a warning and leave blocking_count at 0. Assert the
  # dual-audience judgement stayed quiet on a healthy shape instead.
  check "real_shape_dual_audience_clean_$shape" \
    json_has "$SHAPE_JSON" \
    "not $DUAL_AUDIENCE_CODES & {i.get('code') for i in data.get('warnings', []) + data.get('blocking', [])}"
done

# Clean dual-audience pair should pass alone
CLEAN_JSON="$("$DISCOVERY" --root "$SIBGROUP" \
  "$DISC_DIR/good_a/SKILL.md" \
  "$DISC_DIR/good_b/SKILL.md" 2>/dev/null)" && clean_rc=0 || clean_rc=$?
check "discovery_clean_siblings_exit_zero" test "$clean_rc" -eq 0
check "discovery_clean_no_blocking" \
  json_has "$CLEAN_JSON" "data.get('blocking_count') == 0"

# Purpose-only (human readable, no triggers) must flag missing triggers
PURP="$SCRATCH/purpose_only/SKILL.md"
mkdir -p "$(dirname "$PURP")"
cat > "$PURP" <<'EOF'
---
name: purpose_only
description: Audit gamma modules for structural correctness and packaging readiness across the whole plugin tree.
version: 1.0.0
author: Test
license: MIT
---

# purpose_only
EOF
PURP_JSON="$("$DISCOVERY" "$PURP" 2>/dev/null)" || true
check "discovery_flags_missing_triggers" \
  json_has "$PURP_JSON" \
  "any(i.get('code') == 'description_missing_triggers' for i in data.get('warnings', []))"

# Keyword dump without purpose must flag missing purpose
KEY="$SCRATCH/keywords_only/SKILL.md"
mkdir -p "$(dirname "$KEY")"
cat > "$KEY" <<'EOF'
---
name: keywords_only
description: Use when skill, plugin, agent, hook, commit, wiki, task, guardrail, changelog, prompt, frontmatter, description, SKILL.md.
version: 1.0.0
author: Test
license: MIT
---

# keywords_only
EOF
KEY_JSON="$("$DISCOVERY" "$KEY" 2>/dev/null)" || true
check "discovery_flags_missing_purpose" \
  json_has "$KEY_JSON" \
  "any(i.get('code') == 'description_missing_purpose' for i in data.get('warnings', []))"

# --- discovery_safety: every promised blocking class ----------------------
# The SKILL.md severity paragraph names five blocking classes. Each one is a
# mechanical fact about the file, so each gets a fixture that proves it still
# blocks — otherwise the severity split could quietly drift into "nothing
# blocks at all" while the warning side keeps looking healthy.

MECH="$SCRATCH/mechanical"
rm -rf "${SCRATCH:?}/mechanical"

# Class 1a: absent frontmatter.
mkdir -p "$MECH/no_frontmatter"
printf '# no_frontmatter\n\nBody without any frontmatter.\n' \
  > "$MECH/no_frontmatter/SKILL.md"
NOFM_JSON="$("$DISCOVERY" "$MECH/no_frontmatter/SKILL.md" 2>/dev/null)" \
  && nofm_rc=0 || nofm_rc=$?
check "mech_blocks_frontmatter_missing" \
  json_has "$NOFM_JSON" \
  "any(i.get('code') == 'frontmatter_missing' for i in data.get('blocking', []))"
check "mech_frontmatter_missing_exits_nonzero" test "${nofm_rc:-0}" -ne 0

# Class 1b: unparseable frontmatter — an unquoted scalar carrying a colon.
mkdir -p "$MECH/bad_yaml"
cat > "$MECH/bad_yaml/SKILL.md" <<'EOF'
---
name: bad_yaml
description: Audit widget trees: quickly and thoroughly. Use when checking widgets.
version: 1.0.0
---

# bad_yaml
EOF
BADYAML_JSON="$("$DISCOVERY" "$MECH/bad_yaml/SKILL.md" 2>/dev/null)" || true
check "mech_blocks_yaml_parse" \
  json_has "$BADYAML_JSON" \
  "any(i.get('code') == 'yaml_parse' for i in data.get('blocking', []))"

# Class 2: a missing required field — name, description, or version.
mkdir -p "$MECH/missing_fields"
cat > "$MECH/missing_fields/SKILL.md" <<'EOF'
---
author: Test
license: MIT
---

# missing_fields
EOF
FIELDS_JSON="$("$DISCOVERY" "$MECH/missing_fields/SKILL.md" 2>/dev/null)" || true
check "mech_blocks_name_missing" \
  json_has "$FIELDS_JSON" \
  "any(i.get('code') == 'name_missing' for i in data.get('blocking', []))"
check "mech_blocks_description_missing" \
  json_has "$FIELDS_JSON" \
  "any(i.get('code') == 'description_missing' for i in data.get('blocking', []))"
# Supersedes mech_blocks_version_missing. No harness field reads a skill's
# `version:`, so the requirement belongs to repo convention and the finding
# reports at info — it must not gate the run.
check "mech_reports_version_missing_as_info_not_blocking" \
  json_has "$FIELDS_JSON" \
  "any(i.get('code') == 'version_missing' for i in data.get('info', [])) \
   and not any(i.get('code') == 'version_missing' for i in data.get('blocking', []))"

# Class 3: frontmatter name disagreeing with the directory it sits in.
# Supersedes mech_blocks_name_directory_mismatch. The severity is keyed to the
# recorded harness behaviour rather than to a fixed expectation, so a later
# re-test that changes the record moves both the record and the finding.
mkdir -p "$MECH/alpha"
write_skill "$MECH/alpha" "beta" \
  "Audit beta widgets for correctness and readiness. Use when checking beta widgets or widget metadata."
MISMATCH_JSON="$("$DISCOVERY" "$MECH/alpha/SKILL.md" 2>/dev/null)" || true
check "mech_name_directory_mismatch_severity_matches_the_record" \
  json_has "$MISMATCH_JSON" \
  "(lambda rec: rec is not None and \
     any(i.get('code') == 'name_directory_mismatch' \
         for i in data.get(('blocking' if rec['severity'] == 'blocking' else \
                            'warnings' if rec['severity'] == 'warning' else 'info'), [])))\
   (next((r for r in data.get('severity_records', []) \
          if r.get('code') == 'name_directory_mismatch'), None))"
check "mech_name_directory_mismatch_record_cites_the_load_path" \
  json_has "$MISMATCH_JSON" \
  "all('load path' in r['record'] and 'frontmatter' in r['record'] \
   for r in data.get('severity_records', []) \
   if r.get('code') == 'name_directory_mismatch')"
check "mech_name_directory_mismatch_emitted_once" \
  json_has "$MISMATCH_JSON" \
  "sum(1 for i in data.get('blocking', []) + data.get('warnings', []) \
       + data.get('info', []) if i.get('code') == 'name_directory_mismatch') == 1"

# Class 5: two siblings whose purpose summaries are byte-identical. Class 4
# (parser-hostile characters) is covered by the hostile fixture above.
mkdir -p "$MECH/dup_one" "$MECH/dup_two"
DUP_PURPOSE="Manage the project widget backlog as plain markdown files in widgets."
write_skill "$MECH/dup_one" "dup_one" \
  "$DUP_PURPOSE Use when the user asks about widget backlog work or widget files."
write_skill "$MECH/dup_two" "dup_two" \
  "$DUP_PURPOSE Use when the user wants widget items listed, triaged, or archived."
DUP_JSON="$("$DISCOVERY" --root "$MECH" "$MECH/dup_one/SKILL.md" "$MECH/dup_two/SKILL.md" 2>/dev/null)" \
  && dup_rc=0 || dup_rc=$?
check "mech_blocks_sibling_purpose_not_distinct" \
  json_has "$DUP_JSON" \
  "any(i.get('code') == 'sibling_purpose_not_distinct' for i in data.get('blocking', []))"
check "mech_sibling_purpose_exits_nonzero" test "${dup_rc:-0}" -ne 0
# Distinct purpose summaries on the same shape must stay clean, so the check
# keys on identity rather than on sibling similarity in general.
write_skill "$MECH/dup_two" "dup_two" \
  "Close one completed or parked widget. Use when the user wants widget items listed, triaged, or archived."
DISTINCT_JSON="$("$DISCOVERY" --root "$MECH" "$MECH/dup_one/SKILL.md" "$MECH/dup_two/SKILL.md" 2>/dev/null)" || true
check "mech_distinct_purposes_do_not_block" \
  json_has "$DISTINCT_JSON" \
  "not any(i.get('code') == 'sibling_purpose_not_distinct' for i in data.get('blocking', []))"

# --- discovery_safety: the skill file the harness would load --------------
# Three states make the harness skip a file or load one the author did not
# mean, so each blocks: a file that is not a regular file, a file past the
# harness plugin-skill byte limit, and a directory holding more than one skill
# file. The limit comes from the installed harness CLI's own `Skipping plugin
# skill ... byte limit` message, so it tracks a harness that raises it.

FILEGATE="$SCRATCH/file_gate"
rm -rf "${SCRATCH:?}/file_gate"

BYTE_LIMIT="$(python3 - "$DISCOVERY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ds", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
limit, _ = mod.probe_byte_limit()
print(limit if limit is not None else "")
PY
)"

if [[ -n "$BYTE_LIMIT" ]]; then
  mkdir -p "$FILEGATE/oversized"
  BG_DIR="$FILEGATE/oversized" BG_LIMIT="$BYTE_LIMIT" python3 - <<'PY'
import os
from pathlib import Path

limit = int(os.environ["BG_LIMIT"])
head = (
    "---\nname: oversized\ndescription: Audit oversized widgets for "
    "correctness and packaging readiness. Use when checking oversized "
    "widgets or widget metadata.\nversion: 1.0.0\n---\n\n# oversized\n\n"
)
filler = "Filler prose that pushes this skill past the harness limit. "
body = filler * (((limit - len(head)) // len(filler)) + 2)
Path(os.environ["BG_DIR"], "SKILL.md").write_text(head + body, encoding="utf-8")
PY
  OVER_JSON="$("$DISCOVERY" "$FILEGATE/oversized/SKILL.md" 2>/dev/null)" \
    && over_rc=0 || over_rc=$?
  check "filegate_blocks_over_byte_limit" \
    json_has "$OVER_JSON" \
    "any(i.get('code') == 'skill_file_over_byte_limit' for i in data.get('blocking', []))"
  check "filegate_over_byte_limit_exits_nonzero" test "${over_rc:-0}" -ne 0
  # The message names the harness limit, and that number is the one the probe
  # read out of the installed CLI rather than a constant in the script.
  check "filegate_message_names_the_probed_limit" \
    json_has "$OVER_JSON" \
    "all('$BYTE_LIMIT bytes' in i['message'] \
     for i in data['blocking'] if i.get('code') == 'skill_file_over_byte_limit')"
  check "filegate_check_reports_as_ran_with_the_same_limit" \
    json_has "$OVER_JSON" \
    "any(c['check'] == 'skill_file_byte_limit' and c['status'] == 'ran' \
     and c['limit'] == $BYTE_LIMIT for c in data.get('checks', []))"
  check "filegate_check_source_is_the_probe" \
    json_has "$OVER_JSON" \
    "all(c.get('source') == 'probe' for c in data['checks'] \
     if c['check'] == 'skill_file_byte_limit')"
  check "filegate_probed_limit_traced_to_the_harness_message" \
    json_has "$OVER_JSON" \
    "all('Skipping plugin skill' in c['detail'] for c in data['checks'] \
     if c['check'] == 'skill_file_byte_limit' and c['status'] == 'ran')"
  # A skill comfortably inside the limit draws no finding.
  write_skill "$FILEGATE/small" "small" \
    "Audit small widgets for correctness and readiness. Use when checking small widgets or widget metadata."
  SMALL_JSON="$("$DISCOVERY" "$FILEGATE/small/SKILL.md" 2>/dev/null)" || true
  check "filegate_small_file_draws_no_byte_limit_finding" \
    json_has "$SMALL_JSON" \
    "not any(i.get('code') == 'skill_file_over_byte_limit' \
     for i in data.get('blocking', []) + data.get('warnings', []))"
else
  # No installed CLI yields the limit, so the check runs on the recorded
  # fallback and the summary names that source with its provenance.
  write_skill "$FILEGATE/small" "small" \
    "Audit small widgets for correctness and readiness. Use when checking small widgets or widget metadata."
  SMALL_JSON="$("$DISCOVERY" "$FILEGATE/small/SKILL.md" 2>/dev/null)" || true
  check "filegate_absent_cli_runs_on_the_recorded_fallback" \
    json_has "$SMALL_JSON" \
    "any(c['check'] == 'skill_file_byte_limit' and c['status'] == 'ran' \
     and c.get('source') == 'fallback' and 'recorded' in c['detail'] \
     for c in data.get('checks', []))"
  log "  SKIP  filegate probe detection (no harness CLI yielded a limit; fallback in use)"
fi

# The limit resolution is a pure function, so both branches and the drift
# report are testable on any host whatever CLIs it carries: a probed value
# outranks the recorded fallback and reports drift when they disagree, and an
# absent probe supplies the fallback with its provenance instead of silence.
RESOLVE_OUT="$(python3 - "$DISCOVERY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ds", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
limit, source, detail = mod.resolve_byte_limit(123, "probe detail")
print("probe-wins:", limit, source, "stale" in detail)
limit, source, detail = mod.resolve_byte_limit(None, "no cli anywhere")
print(
    "fallback:",
    limit == mod.FALLBACK_BYTE_LIMIT,
    source,
    mod.FALLBACK_BYTE_LIMIT_PROVENANCE in detail,
    "no cli anywhere" in detail,
)
limit, source, detail = mod.resolve_byte_limit(mod.FALLBACK_BYTE_LIMIT, "d")
print("agreement:", "stale" in detail)
PY
)"
check "filegate_probed_value_outranks_fallback_and_reports_drift" \
  err_has "$RESOLVE_OUT" "probe-wins: 123 probe True"
check "filegate_fallback_supplies_limit_with_provenance_and_reason" \
  err_has "$RESOLVE_OUT" "fallback: True fallback True True"
check "filegate_matching_probe_reports_no_drift" \
  err_has "$RESOLVE_OUT" "agreement: False"
# The recording must stay auditable: the constant carries a provenance line
# naming the build and date it was read from, so a future refresh has a place
# to record itself.
check "filegate_fallback_constant_carries_provenance" \
  grep -q 'FALLBACK_BYTE_LIMIT = ' "$DISCOVERY" \
  && grep -q 'recorded from Claude Code' "$DISCOVERY"

# A directory holding both spellings hands the harness an ambiguous choice.
# The decision is a pure function of the directory listing because a
# case-insensitive filesystem cannot hold both names at once, while the
# harness still meets that state on a case-sensitive one.
AMBIG_OUT="$(python3 - "$DISCOVERY" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("ds", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
print("both", mod.ambiguous_skill_files(["SKILL.md", "skill.md", "README.md"]))
print("one", mod.ambiguous_skill_files(["SKILL.md", "README.md"]))
print("mixedcase", mod.ambiguous_skill_files(["Skill.md", "SKILL.md"]))
PY
)"
check "filegate_ambiguity_detected_for_both_spellings" \
  err_has "$AMBIG_OUT" "both ['SKILL.md', 'skill.md']"
check "filegate_ambiguity_quiet_for_one_spelling" \
  err_has "$AMBIG_OUT" "one []"
check "filegate_ambiguity_detected_for_mixed_case" \
  err_has "$AMBIG_OUT" "mixedcase ['SKILL.md', 'Skill.md']"

# The wiring from that decision to the emitted finding runs on any host by
# injecting the directory listing the harness would see. Without it, the one
# environment the check exists for is the one environment this suite cannot
# reach, and a broken listing-to-finding hop would read as clean. The real
# end-to-end below still runs where the filesystem can hold both names.
write_skill "$FILEGATE/ambiguous_wired" "ambiguous_wired" \
  "Audit wired widgets for correctness and readiness. Use when checking wired widgets or widget metadata."
WIRED_OUT="$(python3 - "$DISCOVERY" "$FILEGATE/ambiguous_wired/SKILL.md" <<'PY'
import importlib.util, sys
from pathlib import Path

spec = importlib.util.spec_from_file_location("ds", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
skill_md = Path(sys.argv[2])


class Entry:
    def __init__(self, name):
        self.name = name


def listing(names):
    def fake(self):
        return [Entry(n) for n in names]

    return fake


def ambiguous():
    report = mod.analyze_skill(skill_md, None, skill_md.parent, "probe")
    return [i for i in report["blocking"] if i["code"] == "skill_file_ambiguous"]


Path.iterdir = listing(["SKILL.md", "skill.md", "README.md"])
found = ambiguous()
print("emitted:", len(found))
print("names:", "SKILL.md, skill.md" in found[0]["message"])
print("evidence:", found[0]["evidence"] == str(skill_md.parent))

Path.iterdir = listing(["SKILL.md", "README.md"])
print("one-spelling:", ambiguous())


def raiser(self):
    raise OSError("listing unavailable")


Path.iterdir = raiser
print("unreadable-dir:", ambiguous())
PY
)"
check "filegate_ambiguity_reaches_the_blocking_bucket" \
  err_has "$WIRED_OUT" "emitted: 1"
check "filegate_ambiguity_finding_names_both_spellings" \
  err_has "$WIRED_OUT" "names: True"
check "filegate_ambiguity_finding_evidences_the_directory" \
  err_has "$WIRED_OUT" "evidence: True"
check "filegate_one_spelling_emits_no_ambiguity_finding" \
  err_has "$WIRED_OUT" "one-spelling: []"
check "filegate_unreadable_directory_emits_no_ambiguity_finding" \
  err_has "$WIRED_OUT" "unreadable-dir: []"

# End to end where the filesystem can hold both names.
if python3 -c "
import os, sys, tempfile
d = tempfile.mkdtemp()
open(os.path.join(d, 'CASEPROBE'), 'w').close()
sys.exit(0 if not os.path.exists(os.path.join(d, 'caseprobe')) else 1)
"; then
  write_skill "$FILEGATE/ambiguous" "ambiguous" \
    "Audit ambiguous widgets for correctness and readiness. Use when checking ambiguous widgets or widget metadata."
  cp "$FILEGATE/ambiguous/SKILL.md" "$FILEGATE/ambiguous/skill.md"
  AMBIG_JSON="$("$DISCOVERY" "$FILEGATE/ambiguous/SKILL.md" 2>/dev/null)" \
    && ambig_rc=0 || ambig_rc=$?
  check "filegate_blocks_ambiguous_skill_file" \
    json_has "$AMBIG_JSON" \
    "any(i.get('code') == 'skill_file_ambiguous' for i in data.get('blocking', []))"
  check "filegate_ambiguous_exits_nonzero" test "${ambig_rc:-0}" -ne 0
else
  log "  SKIP  filegate ambiguous two-file staging (case-insensitive filesystem; the listing-to-finding hop is covered above)"
fi

# A skill file that does not stat as a regular file is skipped by the harness,
# so it blocks. A symlink resolving to a regular file is not one of these: the
# harness stats through the link and loads it, so it stays clean.
mkdir -p "$FILEGATE/broken_link" "$FILEGATE/dir_link/real" "$FILEGATE/good_link"
ln -s /nonexistent/skill-target "$FILEGATE/broken_link/SKILL.md"
ln -s real "$FILEGATE/dir_link/SKILL.md"
write_skill "$FILEGATE/link_source" "good_link" \
  "Audit linked widgets for correctness and readiness. Use when checking linked widgets or widget metadata."
ln -s "$FILEGATE/link_source/SKILL.md" "$FILEGATE/good_link/SKILL.md"

for nonregular in broken_link dir_link; do
  NR_JSON="$("$DISCOVERY" "$FILEGATE/$nonregular/SKILL.md" 2>/dev/null)" \
    && nr_rc=0 || nr_rc=$?
  check "filegate_blocks_non_regular_$nonregular" \
    json_has "$NR_JSON" \
    "any(i.get('code') == 'skill_file_not_regular' for i in data.get('blocking', []))"
  check "filegate_non_regular_exits_nonzero_$nonregular" test "${nr_rc:-0}" -ne 0
  # One fault, one finding: the generic read failure would only repeat it.
  check "filegate_non_regular_reports_one_finding_$nonregular" \
    json_has "$NR_JSON" "data.get('blocking_count') == 1"
done

GOODLINK_JSON="$("$DISCOVERY" "$FILEGATE/good_link/SKILL.md" 2>/dev/null)" || true
check "filegate_symlink_to_regular_file_stays_clean" \
  json_has "$GOODLINK_JSON" "data.get('blocking_count') == 0"

# --- discovery_safety: the convention-owned info tier ---------------------
# A missing `version:` is true of the file while a repo convention owns the
# requirement, so it reports at info and cites the rule where one exists.

INFOTIER="$SCRATCH/info_tier"
rm -rf "${SCRATCH:?}/info_tier"
mkdir -p "$INFOTIER/no_version"
cat > "$INFOTIER/no_version/SKILL.md" <<'EOF'
---
name: no_version
description: Audit versionless widgets for correctness and packaging readiness. Use when checking versionless widgets or widget metadata.
author: Test
license: MIT
---

# no_version
EOF

INFO_JSON="$("$DISCOVERY" --root "$REPO_ROOT" \
  "$INFOTIER/no_version/SKILL.md" 2>/dev/null)" && info_rc=0 || info_rc=$?
check "info_version_missing_is_info_only" \
  json_has "$INFO_JSON" \
  "any(i.get('code') == 'version_missing' for i in data.get('info', [])) \
   and not any(i.get('code') == 'version_missing' \
               for i in data.get('blocking', []) + data.get('warnings', []))"
check "info_version_missing_leaves_blocking_count_zero" \
  json_has "$INFO_JSON" "data.get('blocking_count') == 0"
check "info_version_missing_exits_zero" test "${info_rc:-0}" -eq 0
check "info_count_reported" \
  json_has "$INFO_JSON" "data.get('info_count') == 1"
check "info_message_names_the_owning_convention" \
  json_has "$INFO_JSON" \
  "all('convention' in i['message'] for i in data['info'] \
   if i.get('code') == 'version_missing')"
# Checked inside this repository, the message cites this repo's own rule.
check "info_message_cites_this_repos_version_rule" \
  json_has "$INFO_JSON" \
  "all('1.0.0' in i['message'] and 'AGENTS.md' in i['message'] \
   for i in data['info'] if i.get('code') == 'version_missing')"

# Checked inside a repo whose rule files state no version rule, it says so
# rather than asserting a convention that does not exist.
mkdir -p "$INFOTIER/no_rule/skills/demo"
cp "$INFOTIER/no_version/SKILL.md" "$INFOTIER/no_rule/skills/demo/SKILL.md"
printf '# AGENTS.md\n\n- **Keep every file plain.** Prefer plain markdown.\n' \
  > "$INFOTIER/no_rule/AGENTS.md"
NORULE_JSON="$("$DISCOVERY" --root "$INFOTIER/no_rule" \
  "$INFOTIER/no_rule/skills/demo/SKILL.md" 2>/dev/null)" || true
check "info_message_says_no_rule_was_found" \
  json_has "$NORULE_JSON" \
  "all('state no version rule here' in i['message'] \
   for i in data['info'] if i.get('code') == 'version_missing')"
check "info_no_rule_message_names_no_repo_rule" \
  json_has "$NORULE_JSON" \
  "all('AGENTS.md as' not in i['message'] \
   for i in data['info'] if i.get('code') == 'version_missing')"

# A description that leaks workflow stays a warning with nothing gated on it,
# so the info tier's arrival did not shift a quality judgement's severity.
mkdir -p "$INFOTIER/leaky"
cat > "$INFOTIER/leaky/SKILL.md" <<'EOF'
---
name: leaky
description: Audit leaky widgets for correctness and readiness. Step 1 open the file and then invoke the rewriter. Use when checking leaky widgets or widget metadata.
version: 1.0.0
---

# leaky
EOF
LEAKY_JSON="$("$DISCOVERY" "$INFOTIER/leaky/SKILL.md" 2>/dev/null)" \
  && leaky_rc=0 || leaky_rc=$?
check "info_tier_leaves_workflow_leak_a_warning" \
  json_has "$LEAKY_JSON" \
  "any(i.get('code') == 'description_workflow_leak' for i in data.get('warnings', []))"
check "info_tier_leaves_workflow_leak_unblocking" \
  json_has "$LEAKY_JSON" "data.get('blocking_count') == 0"
check "info_tier_workflow_leak_exits_zero" test "${leaky_rc:-0}" -eq 0

# --- discovery_safety: the shipped skill clears its own gate --------------
# skill_doctor blocking on its own description is the sharpest signal that a
# discovery-safety heuristic has drifted into false positives.

SELF_JSON="$("$DISCOVERY" "$SKILL_MD" 2>/dev/null)" && self_rc=0 || self_rc=$?
check "self_check_exits_zero" test "${self_rc:-0}" -eq 0
check "self_check_no_blocking" \
  json_has "$SELF_JSON" "data.get('blocking_count') == 0"

log ""
log "Passed: $PASS"
log "Failed: $FAIL"
if (( FAIL > 0 )); then
  log "Failed ids: ${FAILED_IDS[*]}"
  exit 1
fi
exit 0
