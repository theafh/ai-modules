#!/usr/bin/env bash
# Bundled-script unit tests for the git_auto_review skill.
#
# Drives the four bundled scripts this skill ships:
#   run_relay.sh     relay init: .gitignore, stem, staleness clear, preseed
#   run_ledger.sh    the regression ledger runner and its exit contract
#   run_snapshot.sh  the round's pre-fix artefacts and the round-1 baseline
#   run_restore.sh   the Restore procedure against the working tree
#
# Every scenario stages its own git sandbox under scratch/<id>/, so no
# scenario touches the host repository's working tree.
# shellcheck disable=SC2329

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/git_auto_review"
SCRIPTS="$SKILL_DIR/scripts"
PXML="$REPO_ROOT/plugins/ai_dev/skills/ai_instruction_formatting/scripts/lint_pseudo_xml.py"
AGENTS_DIR="$REPO_ROOT/plugins/ai_dev/agents"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

PASS=0
FAIL=0
SCENARIOS=0

mkdir -p "$SCRATCH" "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

scenario() {
  local id=$1 desc=$2 body=$3 rc=0
  SCENARIOS=$((SCENARIOS + 1))
  log ""
  log "=== $id  $desc ==="
  "$body" || rc=$?
  if [[ $rc -eq 0 ]]; then
    PASS=$((PASS + 1))
    log "  PASS"
  else
    FAIL=$((FAIL + 1))
    log "  FAIL"
  fi
}

assert_file() {
  local label=$1 path=$2
  if [[ -f "$path" ]]; then return 0; fi
  log "    missing file: $label -> $path"
  return 1
}

assert_eq() {
  local label=$1 actual=$2 expected=$3
  if [[ "$actual" == "$expected" ]]; then return 0; fi
  log "    diff: $label"
  log "      expected: $(printf '%q' "$expected")"
  log "      actual:   $(printf '%q' "$actual")"
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

assert_contains_re() {
  local label=$1 file=$2 pattern=$3
  if grep -Eq -- "$pattern" "$file"; then return 0; fi
  log "    missing pattern: $label"
  log "      file: $file"
  log "      pattern: $pattern"
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

assert_only_model_inherit() {
  local label=$1 file=$2
  if ! grep -Eq '^model:' "$file"; then
    log "    missing model line: $label"
    return 1
  fi
  if grep -E '^model:' "$file" | grep -Fvq 'model: inherit'; then
    log "    non-inherit model line: $label"
    return 1
  fi
  return 0
}

new_sandbox() {
  local id=$1
  local dir="$SCRATCH/$id"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# A repository whose uncommitted change carries the five changes the Restore
# scenario names: a staged tracked change, a change staged then edited again,
# a tracked-file edit, an edit to a pre-existing untracked file, and a newly
# added untracked file.
stage_five_change_repo() {
  local dir=$1
  (
    set -e
    cd "$dir"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    mkdir -p d
    printf 'l1\nl2\nl3\n' > d/staged-only.txt
    printf 'a1\na2\na3\n' > d/staged-then-edited.txt
    printf 'b1\nb2\nb3\n' > d/tracked-edit.txt
    git add .
    git commit --quiet -m "base"
    printf 'l1\nL2\nl3\n' > d/staged-only.txt
    printf 'a1\nA2\nA3\n' > d/staged-then-edited.txt
    printf 'b1\nB2\nb3\n' > d/tracked-edit.txt
    git add d/staged-only.txt d/staged-then-edited.txt
    printf 'a1\nA2\nA3\nA4\n' > d/staged-then-edited.txt
    printf 'b1\nB2\nb3\nb4\n' > d/tracked-edit.txt
    printf 'u1\nU2\n' > d/preexisting-untracked.txt
    printf 'n1\nn2\n' > d/new-untracked.txt
  )
}

# ---------------------------------------------------------------- scenarios

s1_files_and_frontmatter() {
  local ok=true agent
  assert_file "skill" "$SKILL_DIR/SKILL.md" || ok=false
  assert_contains "skill name" "$SKILL_DIR/SKILL.md" "name: git_auto_review" || ok=false
  assert_contains_re "skill semver version" "$SKILL_DIR/SKILL.md" '^version: [0-9]+\.[0-9]+\.[0-9]+$' || ok=false
  assert_contains "skill author" "$SKILL_DIR/SKILL.md" "author: Andreas F. Hoffmann" || ok=false
  assert_contains "skill license" "$SKILL_DIR/SKILL.md" "license: MIT" || ok=false
  assert_contains "skill H1" "$SKILL_DIR/SKILL.md" "# git_auto_review" || ok=false
  for agent in auto_gate_git auto_fixer_git auto_verifier_git; do
    local path="$AGENTS_DIR/$agent.md"
    assert_file "$agent agent" "$path" || ok=false
    assert_contains "$agent name" "$path" "name: $agent" || ok=false
    assert_contains_re "$agent semver version" "$path" '^version: [0-9]+\.[0-9]+\.[0-9]+$' || ok=false
    assert_contains "$agent background false" "$path" "background: false" || ok=false
    assert_contains_re "$agent effort max" "$path" '^effort: max$' || ok=false
    assert_contains_re "$agent codex effort xhigh" "$path" '^model_reasoning_effort: xhigh$' || ok=false
    assert_only_model_inherit "$agent model inherits" "$path" || ok=false
  done
  assert_not_contains_re "gate agent carries no readonly" "$AGENTS_DIR/auto_gate_git.md" '^readonly:' || ok=false
  assert_not_contains_re "fixer agent carries no readonly" "$AGENTS_DIR/auto_fixer_git.md" '^readonly:' || ok=false
  assert_contains "verifier agent readonly" "$AGENTS_DIR/auto_verifier_git.md" "readonly: true" || ok=false
  assert_contains "verifier agent read-only tools" "$AGENTS_DIR/auto_verifier_git.md" "tools: Read, Grep, Glob" || ok=false
  $ok
}

s2_pseudo_xml_lints() {
  python3 "$PXML" --quiet "$SKILL_DIR/SKILL.md" \
    "$AGENTS_DIR/auto_gate_git.md" \
    "$AGENTS_DIR/auto_fixer_git.md" \
    "$AGENTS_DIR/auto_verifier_git.md" \
    >>"$RESULTS" 2>&1
}

s3_lane_classification_single_source() {
  local ok=true skill="$SKILL_DIR/SKILL.md"
  assert_contains "lane block exists" "$skill" "<lane_classification>" || ok=false
  assert_contains "staged scan-locus case" "$skill" "(staged)" || ok=false
  assert_contains "staged re-cite case" "$skill" "re-cite to working tree" || ok=false
  assert_contains "untracked membership case" "$skill" "membership" || ok=false
  assert_contains "catch-all case" "$skill" "Catch-all" || ok=false
  assert_contains "gate loads the block" "$AGENTS_DIR/auto_gate_git.md" "loading the \`git_auto_review\` skill's \`<lane_classification>\` block" || ok=false
  assert_contains "gate reads the lane block from the skill" "$AGENTS_DIR/auto_gate_git.md" "read the block from the skill" || ok=false
  assert_contains "skill carries no second copy in the gate" "$AGENTS_DIR/auto_gate_git.md" "no second copy" || ok=false
  $ok
}

s4_convergence_labels_single_source() {
  local ok=true skill="$SKILL_DIR/SKILL.md" label
  for label in "**Scope anchor.**" "**Severity floor.**" "**Regression ledger.**" "**Decisions.**" "**Stop rule.**"; do
    assert_contains "convergence label $label" "$skill" "$label" || ok=false
  done
  assert_contains "convergence block exists" "$skill" "<convergence>" || ok=false
  assert_contains "round cap default 5" "$skill" "cap of 5 rounds" || ok=false
  assert_contains "round cap override phrase" "$skill" "round cap <N>" || ok=false
  assert_contains "second ledger failure stop" "$skill" "second **Regression ledger.** failure" || ok=false
  assert_contains "second unmapped stop" "$skill" "second \`<audit_delta>\` unmapped-hunk result" || ok=false
  assert_contains "self-written consecutive stop" "$skill" "two consecutive rounds whose qualifying findings all sit in code the loop wrote in an earlier round" || ok=false
  $ok
}

s5_carryover_blocks() {
  local ok=true skill="$SKILL_DIR/SKILL.md" block
  for block in single_gate relay verification_standard audit_delta concurrent_modification_guard agent_failure_policy loop_bounds lane_classification snapshots charter_before_write; do
    assert_contains "carry-over block <$block>" "$skill" "<$block>" || ok=false
  done
  assert_contains "loop bounds points at the stop rule" "$skill" "this block points at that rule by name and restates none of them" || ok=false
  assert_contains "path resolution block" "$skill" "<path_resolution>" || ok=false
  assert_contains "path resolution sibling form" "$skill" "git_review/" || ok=false
  assert_contains "path resolution agents dir" "$skill" "../../agents/" || ok=false
  assert_contains "charter refused class" "$skill" "charter-set-refused" || ok=false
  $ok
}

s6_ledger_contract() {
  local ok=true dir ledger
  dir="$(new_sandbox ledger_contract)"
  ledger="$dir/ledger.txt"

  : > "$ledger"
  bash "$SCRIPTS/run_ledger.sh" --ledger "$ledger" >"$dir/empty.out" 2>&1 \
    || ok=false

  printf 'r1\ttrue\nr2\techo hi\n' > "$ledger"
  bash "$SCRIPTS/run_ledger.sh" --ledger "$ledger" >"$dir/all.out" 2>&1 \
    || ok=false
  assert_contains "per-line number and pass" "$dir/all.out" "line 1: PASS" || ok=false
  assert_contains "second line reported" "$dir/all.out" "line 2: PASS" || ok=false

  printf 'r1\ttrue\nr2\tfalse\nr3\ttrue\n' > "$ledger"
  if bash "$SCRIPTS/run_ledger.sh" --ledger "$ledger" >"$dir/fail.out" 2>&1; then
    log "    ledger with a failing line exited 0"
    ok=false
  fi
  assert_contains "failing line named by 1-based number" "$dir/fail.out" "line 2 failed" || ok=false
  assert_contains "later line still reported" "$dir/fail.out" "line 3: PASS" || ok=false

  printf 'first\tfalse\nsecond\ttrue\n' > "$ledger"
  if bash "$SCRIPTS/run_ledger.sh" --ledger "$ledger" >"$dir/first.out" 2>&1; then
    log "    ledger whose first line fails exited 0"
    ok=false
  fi
  assert_contains "first failing line number is 1" "$dir/first.out" "line 1 failed" || ok=false

  # The path field is the leading tab-separated field; the command field runs.
  printf 'the/path\ttest -f %s/marker\n' "$dir" > "$ledger"
  : > "$dir/marker"
  bash "$SCRIPTS/run_ledger.sh" --ledger "$ledger" >"$dir/field.out" 2>&1 \
    || ok=false
  assert_contains "path field printed" "$dir/field.out" "the/path" || ok=false
  $ok
}

s7_relay_init_and_preseed() {
  local ok=true dir stem
  dir="$(new_sandbox relay_init)"
  stage_five_change_repo "$dir"
  stem="$dir/.git_auto_review/default"

  bash "$SCRIPTS/run_relay.sh" --root "$dir" >"$dir/out1.txt" 2>&1 || ok=false
  assert_file "relay .gitignore" "$dir/.git_auto_review/.gitignore" || ok=false
  assert_eq "relay .gitignore sole line" \
    "$(cat "$dir/.git_auto_review/.gitignore")" "*" || ok=false
  assert_file "stem ledger" "$stem/ledger.txt" || ok=false
  assert_eq "ledger is empty" "$(wc -c < "$stem/ledger.txt" | tr -d ' ')" "0" || ok=false

  # Leftovers from an earlier run, a stale gate-r1.txt among them, are cleared.
  printf 'stale return\n' > "$stem/gate-r1.txt"
  printf 'stale fixer\n' > "$stem/fixer-r1.txt"
  printf 'stale report\n' > "$stem/report.txt"
  # A deliberately pre-seeded pair survives, marker and return together.
  printf 'preseeded r2 return\n' > "$stem/gate-r2.txt"
  : > "$stem/gate-r2.preseed"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >"$dir/out2.txt" 2>&1 || ok=false
  [[ -f "$stem/gate-r1.txt" ]] && { log "    stale gate-r1.txt survived init"; ok=false; }
  [[ -f "$stem/fixer-r1.txt" ]] && { log "    stale fixer-r1.txt survived init"; ok=false; }
  [[ -f "$stem/report.txt" ]] && { log "    stale report.txt survived init"; ok=false; }
  assert_file "preseed pair return survives" "$stem/gate-r2.txt" || ok=false
  assert_file "preseed pair marker survives" "$stem/gate-r2.preseed" || ok=false
  assert_eq "preseed return kept verbatim" \
    "$(cat "$stem/gate-r2.txt")" "preseeded r2 return" || ok=false
  assert_file "ledger recreated" "$stem/ledger.txt" || ok=false

  # The stem is the task file's basename without its extension. The anchor file
  # lives inside this sandbox so the scenario stays self-contained.
  mkdir -p "$dir/tasks"
  printf '# Anchor task\n' > "$dir/tasks/demo_scale.md"
  bash "$SCRIPTS/run_relay.sh" --task tasks/demo_scale.md \
    --root "$dir" >"$dir/out3.txt" 2>&1 || ok=false
  assert_file "task-derived stem directory" \
    "$dir/.git_auto_review/demo_scale/ledger.txt" || ok=false
  $ok
}

s8_snapshot_and_baseline() {
  local ok=true dir stem
  dir="$(new_sandbox snapshot)"
  stage_five_change_repo "$dir"
  stem="$dir/.git_auto_review/default"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false

  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" \
    >"$dir/out1.txt" 2>&1 || ok=false
  assert_file "round-1 pre-fix.patch" "$stem/pre-fix.patch" || ok=false
  assert_file "round-1 pre-fix.untracked.tar" "$stem/pre-fix.untracked.tar" || ok=false
  assert_file "round-1 baseline.patch" "$stem/baseline.patch" || ok=false
  assert_file "round-1 baseline.untracked.tar" \
    "$stem/baseline.untracked.tar" || ok=false
  cp "$stem/baseline.patch" "$dir/baseline.keep"
  cp "$stem/pre-fix.patch" "$dir/prefix.round1"

  # A second round rewrites the pre-fix pair and never the baseline pair.
  printf 'between rounds\n' > "$stem/../probe"
  rm -f "$dir/.git_auto_review/default/../probe"
  printf 'b1\nB2\nROUND2\n' > "$dir/d/tracked-edit.txt"
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" \
    >"$dir/out2.txt" 2>&1 || ok=false
  if ! cmp -s "$stem/baseline.patch" "$dir/baseline.keep"; then
    log "    baseline.patch was rewritten by a later round"
    ok=false
  fi
  if cmp -s "$stem/pre-fix.patch" "$dir/prefix.round1"; then
    log "    pre-fix.patch was not rewritten for the later round"
    ok=false
  fi
  $ok
}

s9_restore_reproduces_captured_state() {
  local ok=true dir stem outside
  dir="$(new_sandbox restore)"
  # Captures and this scenario's own output live OUTSIDE the repository, so
  # the Restore procedure's fixer-added-untracked cleanup cannot touch them.
  outside="$SCRATCH/restore_outside"
  rm -rf "$outside"
  mkdir -p "$outside"
  stage_five_change_repo "$dir"
  stem="$dir/.git_auto_review/default"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false

  local captured="$outside/captured"
  mkdir -p "$captured" || { log "    cannot create $captured"; return 1; }
  local f base
  for f in d/staged-only.txt d/staged-then-edited.txt d/tracked-edit.txt \
      d/preexisting-untracked.txt d/new-untracked.txt; do
    base="cap.$(printf '%s' "$f" | tr / _)"
    cp "$dir/$f" "$captured/$base" || { log "    cannot capture $f"; return 1; }
  done
  (cd "$dir" && git ls-files -s) > "$captured/index.before" || return 1

  # The fixer writes its own edits, including into one captured tracked path.
  printf 'b1\nB2\nFIXER\nb3\nb4\n' > "$dir/d/tracked-edit.txt"
  printf 'FIXER-ONLY\n' > "$dir/d/staged-only.txt"
  printf 'u1\nU2\nFIXER-EXT\n' > "$dir/d/preexisting-untracked.txt"
  printf 'CORRUPT\n' > "$dir/d/new-untracked.txt"
  printf 'fixer added\n' > "$dir/d/fixer-added.txt"

  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$outside/out.txt" 2>&1 || { log "    run_restore.sh exited non-zero"; ok=false; }

  for f in d/staged-only.txt d/staged-then-edited.txt d/tracked-edit.txt \
      d/preexisting-untracked.txt d/new-untracked.txt; do
    base="cap.$(printf '%s' "$f" | tr / _)"
    if ! cmp -s "$dir/$f" "$captured/$base"; then
      log "    $f does not match the captured pre-fix state"
      ok=false
    fi
  done
  (cd "$dir" && git ls-files -s) > "$captured/index.after"
  if ! cmp -s "$captured/index.before" "$captured/index.after"; then
    log "    the index changed across restore"
    ok=false
  fi
  if [[ -e "$dir/d/fixer-added.txt" ]]; then
    log "    the fixer-added untracked file was not deleted"
    ok=false
  fi
  $ok
}

s10_restore_reports_inability() {
  local ok=true dir
  dir="$(new_sandbox restore_missing)"
  stage_five_change_repo "$dir"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  # No snapshot written: restore has no artefact to replay and must say so.
  if bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
      >"$dir/out.txt" 2>&1; then
    log "    run_restore.sh exited 0 with no captured artefacts"
    ok=false
  fi
  assert_contains "restore names the missing artefact" "$dir/out.txt" \
    "pre-fix.patch not found" || ok=false
  $ok
}

s11_makefile_exclude_prune() {
  local ok=true makefile="$REPO_ROOT/Makefile"
  assert_contains "EXCLUDE carries the .git_auto_review prune" "$makefile" \
    "-name .git_auto_review -prune -o" || ok=false
  assert_contains "EXCLUDE comment names the .git_auto_review prune" "$makefile" \
    ".git_auto_review" || ok=false
  assert_contains "EXCLUDE comment names the tests/.gitignore mirror" "$makefile" \
    "tests/.gitignore" || ok=false
  assert_contains "EXCLUDE keeps the workspace prune" "$makefile" \
    "-name workspace -prune -o" || ok=false
  assert_contains "EXCLUDE keeps the scratch prune" "$makefile" \
    "-name scratch -prune -o" || ok=false
  assert_contains "EXCLUDE keeps the __pycache__ prune" "$makefile" \
    "-name __pycache__ -prune -o" || ok=false
  assert_file "tests/.gitignore present" "$REPO_ROOT/tests/.gitignore" || ok=false

  # Exercise the prune itself on a stand-in root: the extracted EXCLUDE
  # expression must hide a markdown file under `.git_auto_review/` while a
  # control markdown file outside it stays in the file list.
  local probe="$SCRATCH/prune_probe"
  rm -rf "$probe"
  mkdir -p "$probe/.git_auto_review/default"
  printf '# stray\n' > "$probe/.git_auto_review/default/bad.md"
  printf '# control\n' > "$probe/control.md"
  local exclude
  exclude="$(sed -n '/^EXCLUDE/,/[^\\]$/p' "$makefile" \
    | sed -e 's/^EXCLUDE[[:space:]]*:=[[:space:]]*//' \
    | tr '\n' ' ' \
    | sed -e 's/[[:space:]]*\\[[:space:]]*/ /g')"
  local listed
  listed="$( (cd "$probe" && eval "find . $exclude -type f -name '*.md' -print") )"
  if [[ "$listed" == *".git_auto_review"* ]]; then
    log "    the prune left a .git_auto_review markdown file in the file list"
    ok=false
  fi
  if [[ "$listed" != *"control.md"* ]]; then
    log "    the prune dropped the control markdown file"
    ok=false
  fi
  $ok
}

s12_isolation_allowlist() {
  local ok=true path="$REPO_ROOT/tests/lib/test_worker_isolation.py"
  assert_contains "isolation allowlist carries git_auto_review_" "$path" \
    "\"git_auto_review_\"," || ok=false
  $ok
}

scenario s1 "new skill and agents exist with aligned frontmatter" s1_files_and_frontmatter
scenario s2 "new pseudo-XML artefacts lint clean" s2_pseudo_xml_lints
scenario s3 "lane classification is stated once and read by the gate" s3_lane_classification_single_source
scenario s4 "convergence states the five labels and the stop conditions once" s4_convergence_labels_single_source
scenario s5 "the carry-over blocks and path resolution exist" s5_carryover_blocks
scenario s6 "run_ledger.sh honours the ledger exit and reporting contract" s6_ledger_contract
scenario s7 "run_relay.sh initialises the relay and preserves marked pairs" s7_relay_init_and_preseed
scenario s8 "run_snapshot.sh writes the pre-fix pair and the once-only baseline" s8_snapshot_and_baseline
scenario s9 "run_restore.sh reproduces the captured worktree, index untouched" s9_restore_reproduces_captured_state
scenario s10 "run_restore.sh reports the state it cannot reproduce" s10_restore_reports_inability
scenario s11 "the Makefile EXCLUDE prune covers a repository-root run" s11_makefile_exclude_prune
scenario s12 "the shared isolation allowlist names the harness prefix" s12_isolation_allowlist

log ""
log "================================================================"
log "  $SCENARIOS scenarios — $PASS pass, $FAIL fail"
log "================================================================"

if (( FAIL > 0 )); then
  exit 1
fi
exit 0
