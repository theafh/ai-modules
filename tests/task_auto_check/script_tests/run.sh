#!/usr/bin/env bash
# Deterministic packaging/content checks for task_auto_check.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

SKILL="$REPO_ROOT/plugins/ai_dev/skills/task_auto_check/SKILL.md"
AGENTS_DIR="$REPO_ROOT/plugins/ai_dev/agents"
PXML="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

scenario() {
  local id=$1 desc=$2 body=$3
  log ""
  log "=== $id  $desc ==="
  "$body"
  local rc=$?
  if [[ $rc -eq 0 ]]; then
    PASS=$((PASS + 1))
    log "  PASS"
  else
    FAIL=$((FAIL + 1))
    FAILED_IDS+=("$id")
    log "  FAIL"
  fi
}

assert_file() {
  local label=$1 path=$2
  if [[ -f "$path" ]]; then return 0; fi
  log "    missing file: $label -> $path"
  return 1
}

assert_contains() {
  local label=$1 file=$2 needle=$3
  if grep -Fq -- "$needle" "$file"; then return 0; fi
  log "    missing text: $label"
  log "      file: $file"
  log "      text: $needle"
  return 1
}

assert_not_contains_re() {
  local label=$1 file=$2 pattern=$3
  if ! grep -Eq -- "$pattern" "$file"; then return 0; fi
  log "    unwanted pattern: $label"
  log "      file: $file"
  log "      pattern: $pattern"
  return 1
}

assert_contains_re() {
  local label=$1 file=$2 pattern=$3
  if grep -Eq -- "$pattern" "$file"; then return 0; fi
  log "    missing pattern: $label"
  log "      file: $file"
  log "      pattern: $pattern"
  return 1
}

assert_only_model_inherit() {
  local label=$1 file=$2
  if ! grep -Eq '^model:' "$file"; then
    log "    missing model line: $label"
    return 1
  fi
  if grep -E '^model:' "$file" | grep -Fvq 'model: inherit'; then
    log "    non-inherit model line: $label"
    grep -E '^model:' "$file" | tee -a "$RESULTS" >&2
    return 1
  fi
  return 0
}

assert_jq_eq() {
  local label=$1 file=$2 expr=$3 expected=$4 actual
  actual="$(jq -r "$expr" "$file" 2>/dev/null)" || {
    log "    jq failed: $label"
    return 1
  }
  if [[ "$actual" == "$expected" ]]; then return 0; fi
  log "    jq mismatch: $label"
  log "      expected: $expected"
  log "      actual:   $actual"
  return 1
}

s1_files_and_frontmatter() {
  local ok=true agent
  assert_file "task_auto_check skill" "$SKILL" || ok=false
  assert_file "auto_drift_task agent" "$AGENTS_DIR/auto_drift_task.md" || ok=false
  assert_contains "auto_drift_task name" "$AGENTS_DIR/auto_drift_task.md" "name: auto_drift_task" || ok=false
  assert_contains_re "auto_drift_task semver version" "$AGENTS_DIR/auto_drift_task.md" '^version: [0-9]+\.[0-9]+\.[0-9]+$' || ok=false
  assert_contains "auto_drift_task model inherits" "$AGENTS_DIR/auto_drift_task.md" "model: inherit" || ok=false
  for agent in auto_gate_task auto_reviewer_task auto_verifier_task; do
    local path="$AGENTS_DIR/$agent.md"
    assert_file "$agent agent" "$path" || ok=false
    assert_contains "$agent name" "$path" "name: $agent" || ok=false
    assert_contains_re "$agent semver version" "$path" '^version: [0-9]+\.[0-9]+\.[0-9]+$' || ok=false
    assert_contains "$agent model inherits" "$path" "model: inherit" || ok=false
  done
  assert_contains "auto_drift_task H1" "$AGENTS_DIR/auto_drift_task.md" "# Auto Drift Task" || ok=false
  assert_contains "auto_gate_task H1" "$AGENTS_DIR/auto_gate_task.md" "# Auto Gate Task" || ok=false
  assert_contains "auto_reviewer_task H1" "$AGENTS_DIR/auto_reviewer_task.md" "# Auto Reviewer Task" || ok=false
  assert_contains "auto_verifier_task H1" "$AGENTS_DIR/auto_verifier_task.md" "# Auto Verifier Task" || ok=false
  assert_contains "skill name" "$SKILL" "name: task_auto_check" || ok=false
  assert_contains_re "skill semver version" "$SKILL" '^version: [0-9]+\.[0-9]+\.[0-9]+$' || ok=false
  $ok
}

s2_gate_is_task_check() {
  local ok=true
  assert_contains "gate uses task_check verbatim" "$SKILL" "Use \`task_check\` verbatim as the gate." || ok=false
  assert_contains "base readiness checklist cited" "$SKILL" "<readiness_checklist>" || ok=false
  assert_contains "status writer enum keeps task_check as the auto_check-mode writer" "$AGENTS_DIR/auto_gate_task.md" "status writer: <task_check|deferred to the auto_shaper_task writer|none>" || ok=false
  assert_contains "shaper read-side mode withholds the stamp" "$AGENTS_DIR/auto_gate_task.md" "withhold the stamp" || ok=false
  assert_contains "no second readiness bar" "$AGENTS_DIR/auto_gate_task.md" "do not define a second readiness bar" || ok=false
  assert_contains "task_check remains read-only body gate" "$REPO_ROOT/plugins/ai_dev/skills/task_check/SKILL.md" "it moves no file and changes no body content or other frontmatter" || ok=false
  assert_not_contains_re "task_check has no drift or git-history step" "$REPO_ROOT/plugins/ai_dev/skills/task_check/SKILL.md" "auto_drift_task|git log|--follow|committed-intent|git-history|git history" || ok=false
  assert_not_contains_re "auto_gate_task has no drift check" "$AGENTS_DIR/auto_gate_task.md" "auto_drift_task|git log|--follow|committed-intent" || ok=false
  $ok
}

s3_reviewer_and_verifier_boundaries() {
  local ok=true
  assert_contains "reviewer cites compact rule" "$SKILL" "Compact only to the implementable floor" || ok=false
  assert_contains "reviewer cites state-once rule" "$SKILL" "State once" || ok=false
  assert_contains "reviewer cites acceptance contract" "$SKILL" "Acceptance** contract" || ok=false
  assert_contains "reviewer cites rewrite rule" "$SKILL" "Rewrite in place, don't append" || ok=false
  assert_contains "reviewer does not write files" "$AGENTS_DIR/auto_reviewer_task.md" "Do not write files" || ok=false
  assert_contains "verifier rejects by default" "$AGENTS_DIR/auto_verifier_task.md" "Reject by default." || ok=false
  assert_contains "fidelity check" "$AGENTS_DIR/auto_verifier_task.md" "dedicated fidelity check" || ok=false
  assert_contains "verifier preserves human-input boundaries" "$AGENTS_DIR/auto_verifier_task.md" "Preserve explicit human-input boundaries." || ok=false
  $ok
}

s4_loop_controls_and_boundaries() {
  local ok=true
  assert_contains "default hard cap 5" "$SKILL" "Use a hard cap of 5 rounds" || ok=false
  assert_contains "cap override" "$SKILL" "positive integer override" || ok=false
  assert_contains "scope/focus/complexity split boundary" "$SKILL" "scope-sizing, focus, or complexity defects" || ok=false
  assert_contains "split routed not applied" "$AGENTS_DIR/auto_verifier_task.md" "For \`task_auto_check\`, keep structural split proposals as human-routed summaries" || ok=false
  assert_contains "no agreement counting in skill" "$SKILL" "never count agreement, votes, consensus, or majority" || ok=false
  assert_contains "no agreement counting in reviewer" "$AGENTS_DIR/auto_reviewer_task.md" "Use no agreement, voting, confidence tally, or majority language." || ok=false
  assert_contains "foreign stance off by default" "$SKILL" "The default is single-model operation with no foreign-model stance." || ok=false
  assert_only_model_inherit "no pinned agent model" "$AGENTS_DIR/auto_gate_task.md" || ok=false
  assert_only_model_inherit "no pinned drift model" "$AGENTS_DIR/auto_drift_task.md" || ok=false
  assert_only_model_inherit "no pinned reviewer model" "$AGENTS_DIR/auto_reviewer_task.md" || ok=false
  assert_only_model_inherit "no pinned verifier model" "$AGENTS_DIR/auto_verifier_task.md" || ok=false
  $ok
}

s5_family_rosters() {
  local ok=true file
  for file in \
    "$REPO_ROOT/plugins/ai_dev/skills/task/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_create/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_check/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_select/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_implement/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_audit/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_finish/SKILL.md" \
    "$REPO_ROOT/plugins/ai_dev/skills/task_fix/SKILL.md"; do
    assert_contains "family roster includes task_auto_check in ${file#"$REPO_ROOT"/}" "$file" "task_auto_check\` — autonomously repair one task until \`task_check\` reports ready" || ok=false
  done
  $ok
}

s6_docs_and_metadata_registered() {
  local ok=true canon
  canon="$(jq -r '.version' "$REPO_ROOT/plugins/ai_dev/.claude-plugin/plugin.json" 2>/dev/null)"
  if [[ ! "$canon" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log "    claude plugin version is not semver: '$canon'"
    ok=false
  fi
  assert_jq_eq "codex plugin version lockstep" "$REPO_ROOT/plugins/ai_dev/.codex-plugin/plugin.json" '.version' "$canon" || ok=false
  assert_jq_eq "codex marketplace version lockstep" "$REPO_ROOT/.agents/plugins/marketplace.json" '.plugins[] | select(.name=="ai_dev") | .version' "$canon" || ok=false
  assert_jq_eq "claude marketplace version lockstep" "$REPO_ROOT/.claude-plugin/marketplace.json" '.plugins[] | select(.name=="ai_dev") | .version' "$canon" || ok=false
  assert_contains "plugin README skill" "$REPO_ROOT/plugins/ai_dev/README.md" "**task_auto_check**" || ok=false
  assert_contains "plugin README drift agent" "$REPO_ROOT/plugins/ai_dev/README.md" "**auto_drift_task**" || ok=false
  assert_contains "plugin README gate agent" "$REPO_ROOT/plugins/ai_dev/README.md" "**auto_gate_task**" || ok=false
  assert_contains "root README skill" "$REPO_ROOT/README.md" "task_auto_check/" || ok=false
  assert_contains "root README drift agent" "$REPO_ROOT/README.md" "auto_drift_task.md" || ok=false
  assert_contains "root README agents" "$REPO_ROOT/README.md" "auto_verifier_task.md" || ok=false
  $ok
}

s7_pseudo_xml_lints() {
  python3 "$PXML" --quiet "$SKILL" "$AGENTS_DIR/auto_drift_task.md" \
    "$AGENTS_DIR/auto_gate_task.md" \
    "$AGENTS_DIR/auto_reviewer_task.md" "$AGENTS_DIR/auto_verifier_task.md" \
    >>"$RESULTS" 2>&1
}

s8_mechanical_lint_finalization() {
  local ok=true base="$REPO_ROOT/plugins/ai_dev/skills/task/SKILL.md" fix="$REPO_ROOT/plugins/ai_dev/skills/task_fix/SKILL.md" count
  assert_contains "base owns authoritative lint fix set" "$base" "The **mechanically fixable lint finding set** is the authoritative type list" || ok=false
  count="$(grep -R "authoritative type list" "$REPO_ROOT/plugins/ai_dev/skills/task" "$REPO_ROOT/plugins/ai_dev/skills/task_auto_check" "$REPO_ROOT/plugins/ai_dev/skills/task_fix" | wc -l | tr -d ' ')"
  if [[ "$count" != "1" ]]; then
    log "    authoritative list appears $count times across task/task_auto_check/task_fix"
    ok=false
  fi
  assert_contains "description budget fix named" "$base" "**Description budget**" || ok=false
  assert_contains "broken local link fix named" "$base" "**Local markdown links**" || ok=false
  assert_contains "wikilink and footnote conversion named" "$base" "**Standard-markdown conversion**" || ok=false
  assert_contains "task_auto_check finalization tag" "$SKILL" "<finalize_mechanical_lint>" || ok=false
  assert_contains "immediate ready path finalizes lint" "$SKILL" "When every citation survives, the \`ready\` stamp stands and the run proceeds to \`<finalize_mechanical_lint>\` as on any other \`ready\` verdict." || ok=false
  assert_contains "mechanical path skips reviewer verifier agents" "$SKILL" "do not spawn \`auto_reviewer_task\` or \`auto_verifier_task\` for mechanical lint findings" || ok=false
  assert_contains "mechanical path does not re-gate readiness" "$SKILL" "do not re-run \`task_check\` after applying them" || ok=false
  assert_contains "output reports mechanical fixes and surfaced findings" "$SKILL" "the base \`<lint>\` findings applied, the target-file findings surfaced-but-not-fixed" || ok=false
  assert_contains "task_fix cites base lint set" "$fix" "applying the base \`<lint>\` mechanically fixable finding set across the whole tree" || ok=false
  $ok
}

s9_intent_drift_boundary() {
  local ok=true drift="$AGENTS_DIR/auto_drift_task.md" check="$REPO_ROOT/plugins/ai_dev/skills/task_check/SKILL.md" gate="$AGENTS_DIR/auto_gate_task.md"
  assert_contains "drift agent follows renames" "$drift" "git log --follow" || ok=false
  assert_contains "drift agent earliest committed baseline" "$drift" "earliest committed" || ok=false
  assert_contains "drift agent full history not previous commit" "$drift" "not merely the previous commit" || ok=false
  assert_contains "drift agent meaning-preserving accretion clean" "$drift" "Clean accretion" || ok=false
  assert_contains "drift agent resolved open decisions clean" "$drift" "resolved labeled open decisions" || ok=false
  assert_contains "drift agent intent-preserving clarification clean" "$drift" "intent-preserving clarifications" || ok=false
  assert_contains "drift agent flags changed objective only" "$drift" "changes what the task is about" || ok=false
  assert_contains "drift agent read-only" "$drift" "Edit no files, revert no content, move no task, and stamp no frontmatter." || ok=false
  assert_contains "drift agent low-confidence clean" "$drift" "low_confidence_clean" || ok=false
  assert_contains "task_auto_check resolves drift agent" "$SKILL" "auto_drift_task" || ok=false
  assert_contains "drift boundary tag exists" "$SKILL" "<intent_drift_boundary>" || ok=false
  assert_contains "drift invoked once at freeze" "$SKILL" "Invoke \`auto_drift_task\` once at freeze time, before the first \`<gate>\` call and any repair." || ok=false
  assert_contains "drift human intention message names the drifted field" "$SKILL" "Attention: this task's Title appears to have already drifted from its original intent." || ok=false
  assert_contains "drift human routes" "$SKILL" "human-routed through the same surfaced stuck channel" || ok=false
  assert_contains "drift never auto-repairs recovered origin" "$SKILL" "never auto-repairs toward the recovered original intent" || ok=false
  assert_contains "drift leaves body unchanged" "$SKILL" "leave the task body unchanged" || ok=false
  assert_contains "drift keeps frozen intent" "$SKILL" "keep \`<frozen_intent>\` intact" || ok=false
  assert_contains "clean drift result proceeds silently" "$SKILL" "proceed without surfacing the intention check" || ok=false
  assert_not_contains_re "task_check unchanged for drift" "$check" "auto_drift_task|committed-intent|git log|--follow" || ok=false
  assert_not_contains_re "auto_gate_task unchanged for drift" "$gate" "auto_drift_task|committed-intent|git log|--follow" || ok=false
  $ok
}

s10_failure_policy_and_rebaseline() {
  local ok=true gate="$AGENTS_DIR/auto_gate_task.md" drift="$AGENTS_DIR/auto_drift_task.md" reviewer="$AGENTS_DIR/auto_reviewer_task.md" verifier="$AGENTS_DIR/auto_verifier_task.md"
  assert_contains "failure policy tag exists" "$SKILL" "<agent_failure_policy>" || ok=false
  assert_contains "transient failures retry once" "$SKILL" "retry it once" || ok=false
  assert_contains "unassessable skips the retry as a completed verdict" "$SKILL" "skips the retry" || ok=false
  assert_contains "helper failure stops the run for the user" "$SKILL" "stop the run as a helper-failure stop" || ok=false
  assert_contains "user decides the degraded route" "$SKILL" "act only on their explicit choice" || ok=false
  assert_contains "no automatic recovery" "$SKILL" "no degraded alternative, retry loop, or recovery runs automatically" || ok=false
  assert_contains "alternatives presented never taken unprompted" "$SKILL" "A degraded alternative is presented, never taken unprompted" || ok=false
  assert_contains "headless stop is the final output" "$SKILL" "the error report ending in the question is the run's final output" || ok=false
  assert_contains "no helper result is improvised" "$SKILL" "never role-plays a missing gate, drift, reviewer, or verifier result" || ok=false
  assert_contains "no-spawn harness stops before freeze" "$SKILL" "no agent-spawn mechanism" || ok=false
  assert_contains "no inline helper roles" "$SKILL" "instead of executing helper roles inline" || ok=false
  assert_contains "guard re-baselines after each gate verdict" "$SKILL" "adopt the post-gate content as the new baseline" || ok=false
  assert_contains "gate verdict carries unassessable" "$gate" "status: <ready|checked|unassessable>" || ok=false
  assert_contains "gate verdict carries stamp disposition" "$gate" "stamp: <written|intended-only|none>" || ok=false
  assert_contains "drift verdict carries unassessable" "$drift" "classification: <clean|drift|low_confidence_clean|unassessable>" || ok=false
  assert_contains "reviewer proposal carries unassessable" "$reviewer" "proposal_kind: <edit|split_summary|relocation_summary|coherence_repair_summary|no_proposal|unassessable>" || ok=false
  assert_contains "verifier decision carries unassessable" "$verifier" "decision: <rejected|human_routed|unassessable>" || ok=false
  assert_contains "verifier approved edits non-overlapping" "$verifier" "mutually non-overlapping" || ok=false
  assert_contains "skill human-routes majority-body removal" "$SKILL" "remove the majority of the task body" || ok=false
  assert_contains "verifier human-routes majority-body removal" "$verifier" "removes the majority of the task body" || ok=false
  assert_contains "reviewer receives frozen title" "$reviewer" "the frozen \`# Title\` and \`## Goal\`" || ok=false
  assert_contains "verifier fidelity uses frozen title" "$verifier" "judging a title-changing edit against the frozen \`# Title\`" || ok=false
  $ok
}

scenario s1 "new skill and agents exist with aligned frontmatter" s1_files_and_frontmatter
scenario s2 "task_check remains the single readiness gate" s2_gate_is_task_check
scenario s3 "reviewer/verifier roles are separated and intent-safe" s3_reviewer_and_verifier_boundaries
scenario s4 "loop controls cover cap, stuck states, no voting, no model pins" s4_loop_controls_and_boundaries
scenario s5 "task family rosters include task_auto_check" s5_family_rosters
scenario s6 "README and plugin metadata register the new artefacts" s6_docs_and_metadata_registered
scenario s7 "new pseudo-XML artefacts lint" s7_pseudo_xml_lints
scenario s8 "mechanical lint finalization is single-sourced and wired" s8_mechanical_lint_finalization
scenario s9 "freeze-time intent drift is read-only and human-routed" s9_intent_drift_boundary
scenario s10 "agent failure policy, unassessable states, and guard re-baseline are pinned" s10_failure_policy_and_rebaseline

log ""
log "================================================================"
log "  $((PASS + FAIL)) scenarios — $PASS pass, $FAIL fail"
log "================================================================"

if (( FAIL > 0 )); then
  log "Failed scenarios: ${FAILED_IDS[*]}"
  exit 1
fi
