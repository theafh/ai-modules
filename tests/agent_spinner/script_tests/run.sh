#!/usr/bin/env bash
# script_tests/run.sh — static contract checks for agent_spinner.
#
# agent_spinner ships no bundled scripts, so this surface covers the
# filesystem and grep acceptance items instead: frontmatter and size budgets,
# one block per named contract, the six shape tags and their four elements,
# the per-harness-fact greps that must stay empty, the reference set, the
# trigger eval set, and registration lockstep.
#
# The behavioural items live in evals/, driven by evals/run.py.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/agent_spinner"
SKILL="$SKILL_DIR/SKILL.md"
REFS="$SKILL_DIR/references"
TRIGGERS="$REPO_ROOT/tests/trigger_evals/agent_spinner.json"

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

# section_has <file> <tag> <pattern> — match inside one pseudo-XML block, so a
# pin proves the rule landed in the section that owns it.
section_has() {
  awk -v tag="$2" '
    index($0, "<" tag ">") { inside = 1 }
    inside                 { print }
    index($0, "</" tag ">") { inside = 0 }
  ' "$1" | grep -Eq "$3"
}

bytes_under() { [[ "$(wc -c < "$1")" -lt "$2" ]]; }

description_under() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r"^description: (.*?)(?=\n[a-z-]+:)", fm, re.S | re.M).group(1).strip()
sys.exit(0 if len(desc) < int(sys.argv[2]) else 1)
PY
}

description_has() {
  python3 - "$1" "$2" <<'PY'
import re, sys
text = open(sys.argv[1]).read()
fm = re.search(r"^---\n(.*?)\n---", text, re.S).group(1)
desc = re.search(r"^description: (.*?)(?=\n[a-z-]+:)", fm, re.S | re.M).group(1)
sys.exit(0 if re.search(sys.argv[2], desc, re.I) else 1)
PY
}

# tree_lacks <dir> <pattern> — the grep acceptance items, which pass by
# returning nothing across the skill and its references alike.
tree_lacks() { ! grep -REiq "$2" "$1"; }

# product_hits_cite_portability <dir> — every line naming a target product
# also names harness_portability. Zero product hits satisfies it vacuously,
# which is the shape the skill actually ships in.
product_hits_cite_portability() {
  local dir="$1" hits
  hits="$(grep -REin 'claude|codex|cursor|antigravity|opencode|copilot|gemini|anthropic|openai' "$dir" || true)"
  [[ -z "$hits" ]] && return 0
  ! printf '%s\n' "$hits" | grep -qv 'harness_portability'
}

# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"

printf 'agent_spinner script_tests\n'

# --- frontmatter and budgets ------------------------------------------------
check "SKILL.md exists" test -f "$SKILL"
check "frontmatter name: agent_spinner" file_has "$SKILL" '^name: agent_spinner$'
# Test Integrity: a grader fix. The skill must carry a semantic version, and a
# literal pin breaks on every commit-time bump (the reason
# tests/lib/plugin_version.sh gives against literal pins), so the check
# asserts the shape.
check "frontmatter version is semver" file_has "$SKILL" '^version: [0-9]+\.[0-9]+\.[0-9]+$'
check "H1 matches the frontmatter name" file_has "$SKILL" '^# agent_spinner$'
check "SKILL.md under 25000 bytes" bytes_under "$SKILL" 25000
check "description under 1500 characters" description_under "$SKILL" 1500

for word in orchestrat fan-out verif parallel; do
  check "description carries the '$word' trigger word" \
    description_has "$SKILL" "$word"
done
check "description routes task requests to the task_* family" \
  description_has "$SKILL" 'task_\*'
check "description routes wiki requests to wiki_fix" \
  description_has "$SKILL" 'wiki_fix'

# --- one block per named contract -------------------------------------------
CONTRACTS=(
  invocation_boundary capability_probe degradation selector shapes width
  phase_plan run_economy coverage_tradeoff containment delegation_depth
  prompt_assembly checking confirmation_provenance helper_failure remediation
  run_state aggregation reporting judgement
)
for tag in "${CONTRACTS[@]}"; do
  check "block <$tag> present" file_has "$SKILL" "<$tag>"
done

# --- the six shapes, each with its four elements ----------------------------
SHAPES=(
  per_artifact_fan_out lens_panel paired_refute_check
  judge_panel completeness_critic single_writer_validator
)
for shape in "${SHAPES[@]}"; do
  check "shape <$shape> present" file_has "$SKILL" "<$shape>"
  for element in Trigger Width 'Prompt skeleton' Return; do
    check "shape <$shape> states its $element" \
      section_has "$SKILL" "$shape" "\\*\\*$element\\*\\*"
  done
done
check "the six shapes sit inside <shapes>" \
  bash -c "awk '/<shapes>/,/<\\/shapes>/' '$SKILL' | grep -c '<per_artifact_fan_out>\\|<lens_panel>\\|<paired_refute_check>\\|<judge_panel>\\|<completeness_critic>\\|<single_writer_validator>' | grep -q '^6$'"

# --- capability probe -------------------------------------------------------
check "capability_probe names the delegation surface" \
  section_has "$SKILL" capability_probe 'delegation surface'
check "capability_probe names a read-only lever" \
  section_has "$SKILL" capability_probe 'read-only lever'
check "capability_probe names a depth or effort control" \
  section_has "$SKILL" capability_probe 'depth or effort control'
check "capability_probe names concurrency" \
  section_has "$SKILL" capability_probe 'two helpers run at once'
check "capability_probe separates deployment from callability" \
  section_has "$SKILL" capability_probe 'evidence that the file deployed, not evidence that it can be called'
check "capability_probe resolves an unestablished capability to absent" \
  section_has "$SKILL" capability_probe 'resists establishment to absent'

# --- degradation, selector, width, depth ------------------------------------
check "degradation names the inline floor" \
  section_has "$SKILL" degradation 'Inline floor'
check "degradation honours a governing stop-and-ask boundary" \
  section_has "$SKILL" degradation 'stop-and-ask boundary'
check "degradation claims no wall-clock benefit" \
  section_has "$SKILL" degradation 'no wall-clock benefit'
check "selector carries the residual smallest-covering rule" \
  section_has "$SKILL" selector 'smallest shape that covers it'
check "width derives breadth from the written-out list" \
  section_has "$SKILL" width 'never a round number'
check "delegation_depth holds the run to one level" \
  section_has "$SKILL" delegation_depth 'delegates no part of it'

# --- the grep items that must stay empty ------------------------------------
check "no per-harness frontmatter keys or tool identifiers" \
  tree_lacks "$SKILL_DIR" '^[[:space:]]*(tools|allowed-?tools|disallowed-?tools|subagent_type|argument-hint|disable-model-invocation|reasoningEffort)[[:space:]]*:|Task\(|Bash\(|WebFetch|str_replace|apply_patch'
check "no harness agent directory paths" \
  tree_lacks "$SKILL_DIR" '\.claude/|\.codex/|\.cursor/|\.opencode/|\.agents/|\.github/'
check "no sandbox mode values" \
  tree_lacks "$SKILL_DIR" 'bypassPermissions|acceptEdits|danger-full-access|workspace-write|--permission-mode|dangerously-skip'
check "every target product name cites harness_portability" \
  product_hits_cite_portability "$SKILL_DIR"
check "no instruction to write a global rules or agent-config file" \
  tree_lacks "$SKILL_DIR" 'AGENTS\.md|CLAUDE\.md|GEMINI\.md|cursorrules|settings\.json|global (rules|instructions)|standing-instructions file'

# --- the advisory direction stays one-way -----------------------------------
check "no agent definition cites agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/agents" 'agent_spinner'
check "task_auto_check does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/skills/task_auto_check" 'agent_spinner'
check "task_fix does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/ai_dev/skills/task_fix" 'agent_spinner'
check "knowledge_management does not cite agent_spinner" \
  tree_lacks "$REPO_ROOT/plugins/knowledge_management" 'agent_spinner'
check "the skill bundles no agent definitions" \
  bash -c "[[ ! -d '$SKILL_DIR/agents' ]]"
check "the skill bundles no runtime scripts" \
  bash -c "[[ ! -d '$SKILL_DIR/scripts' ]]"

# --- references -------------------------------------------------------------
check "references/role-prompts.md exists" test -f "$REFS/role-prompts.md"
check "references/report-shapes.md exists" test -f "$REFS/report-shapes.md"
check "references/degradation-examples.md exists" test -f "$REFS/degradation-examples.md"
check "references/variants.md exists" test -f "$REFS/variants.md"
for role in 'Producing pass' 'Lens pass' 'Checking pass' 'Synthesis pass'; do
  check "role-prompts.md carries the $role template" \
    file_has "$REFS/role-prompts.md" "^## $role$"
done
check "variants.md carries the information-isolation variant" \
  file_has "$REFS/variants.md" 'Information isolation between concurrent helpers'
check "variants.md carries the replicated-draw variant" \
  file_has "$REFS/variants.md" 'Replicated draws returned unreduced'
check "every template opens with an action rather than a prohibition" \
  python3 -c "
import re, sys
t = open('$REFS/role-prompts.md').read()
blocks = re.findall(r'\`\`\`text\n(.*?)\`\`\`', t, re.S)
sys.exit(0 if blocks and all(
    re.match(r'(Read|Write|Open|Start|Run|List|Check|Return)\b',
             next(l for l in b.splitlines() if l.strip()))
    for b in blocks) else 1)
"
check "no template claims precedence over the surrounding conversation" \
  tree_lacks "$REFS" 'takes? precedence|override[s]? (any|all|the)|ignore (all |any )?(previous|prior|earlier)|supersede[s]? (any|all)|regardless of (any|all)|highest authority'

# --- trigger evals ----------------------------------------------------------
check "trigger eval set exists" test -f "$TRIGGERS"
check "trigger eval set is valid JSON" jq empty "$TRIGGERS"
check "trigger set carries should_trigger true queries" \
  bash -c "jq -e 'map(select(.should_trigger == true)) | length >= 5' '$TRIGGERS'"
check "trigger set carries should_trigger false queries" \
  bash -c "jq -e 'map(select(.should_trigger == false)) | length >= 5' '$TRIGGERS'"
for territory in 'task_check\|readiness' 'backlog' 'wiki' 'pull request' 'guardrail' 'harness\|Codex'; do
  check "trigger set draws a negative from $territory territory" \
    bash -c "jq -r '.[] | select(.should_trigger == false) | .query' '$TRIGGERS' | grep -qi '$territory'"
done

# --- registration -----------------------------------------------------------
check "listed in .claude-plugin/plugin.json description" \
  file_has "$REPO_ROOT/plugins/ai_dev/.claude-plugin/plugin.json" 'agent_spinner'
check "listed in .codex-plugin/plugin.json description" \
  file_has "$REPO_ROOT/plugins/ai_dev/.codex-plugin/plugin.json" 'agent_spinner'
check "listed in the Claude marketplace registration" \
  file_has "$REPO_ROOT/.claude-plugin/marketplace.json" 'agent_spinner'
check "listed in the Codex marketplace registration" \
  file_has "$REPO_ROOT/.agents/plugins/marketplace.json" 'agent_spinner'
check "listed in the plugin README" \
  file_has "$REPO_ROOT/plugins/ai_dev/README.md" 'agent_spinner'
check "listed in the root README layout tree" \
  bash -c "grep -Eq '── agent_spinner/' '$REPO_ROOT/README.md'"
check "listed in the root README skill list" \
  bash -c "grep -Eq '\\*\\*agent_spinner\\*\\*' '$REPO_ROOT/README.md'"
check "the wiki concept page points at the skill" \
  file_has "$REPO_ROOT/wiki/concepts/agent-delegated-automation.md" 'agent_spinner'
check_plugin_version_lockstep ai_dev

printf '\n%d passed, %d failed\n' "$pass" "$fail"
if (( fail > 0 )); then
  printf 'failures:\n'
  for f in "${failures[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi
exit 0
