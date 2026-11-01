#!/usr/bin/env bash
# Bundled-script unit tests for the git_auto_review skill.
#
# Drives the five bundled scripts this skill ships:
#   run_relay.sh       relay init: .gitignore, stem, staleness clear, preseed
#   run_ledger.sh      the regression ledger runner and its exit contract
#   run_snapshot.sh    the round's pre-fix artefacts and the round-1 baseline
#   run_round_diff.sh  the round's fixer-write diff over the pre-fix state
#   run_restore.sh     the Restore procedure against the working tree
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
GRADE_SCRIPT="$REPO_ROOT/tests/git_auto_review/evals/grade.sh"

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
  assert_contains "branch-range re-cite case" "$skill" "Branch-range re-cite to working tree." || ok=false
  assert_contains "untracked membership case" "$skill" "membership" || ok=false
  assert_contains "catch-all case" "$skill" "Catch-all" || ok=false
  assert_contains "gate loads the block" "$AGENTS_DIR/auto_gate_git.md" "loading the \`git_auto_review\` skill's \`<lane_classification>\` block" || ok=false
  assert_contains "gate reads the lane block from the skill" "$AGENTS_DIR/auto_gate_git.md" "read the block from the skill" || ok=false
  assert_contains "skill carries no second copy in the gate" "$AGENTS_DIR/auto_gate_git.md" "no second copy" || ok=false
  $ok
}

s4_convergence_labels_single_source() {
  local ok=true skill="$SKILL_DIR/SKILL.md" label
  for label in "**Scope anchor.**" "**Regression ledger.**" "**Decisions.**" "**Stop rule.**"; do
    assert_contains "convergence label $label" "$skill" "$label" || ok=false
  done
  assert_not_contains_re "skill drops the severity floor block" "$skill" '<severity_floor>' || ok=false
  assert_not_contains_re "skill drops the severity floor label" "$skill" 'Severity floor' || ok=false
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
  # Reproduction files sit directly in the stem, and the relay's .gitignore
  # makes git ignore them.
  printf 'exit 0\n' > "$stem/reproduction-r1-finding-1.sh"
  assert_eq "a reproduction in the stem is ignored" \
    "$(cd "$dir" && git status --porcelain --untracked-files=all -- .git_auto_review)" "" \
    || ok=false

  # Leftovers from an earlier run, a stale gate-r1.txt and a stale
  # reproduction among them, are cleared.
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
  [[ -f "$stem/reproduction-r1-finding-1.sh" ]] \
    && { log "    stale reproduction survived init"; ok=false; }
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

  # A task path that does not resolve to a readable regular file is rejected as
  # an environment error before any relay state exists for that stem. Each
  # value below would derive its own stem, so the absence checks are meaningful.
  local rc=0
  bash "$SCRIPTS/run_relay.sh" --task tasks/missing_anchor.md \
    --root "$dir" >"$dir/out4.txt" 2>&1 || rc=$?
  assert_eq "missing task path exit code" "$rc" "2" || ok=false
  assert_contains "missing task path named" "$dir/out4.txt" \
    "tasks/missing_anchor.md" || ok=false
  [[ -e "$dir/.git_auto_review/missing_anchor" ]] \
    && { log "    missing task path created a stem directory"; ok=false; }

  rc=0
  bash "$SCRIPTS/run_relay.sh" --task tasks \
    --root "$dir" >"$dir/out5.txt" 2>&1 || rc=$?
  assert_eq "directory task path exit code" "$rc" "2" || ok=false
  assert_contains "directory task path named" "$dir/out5.txt" "file: tasks" || ok=false
  [[ -e "$dir/.git_auto_review/tasks" ]] \
    && { log "    directory task path created a stem directory"; ok=false; }

  printf '# Unreadable anchor\n' > "$dir/tasks/demo_locked.md"
  chmod 000 "$dir/tasks/demo_locked.md"
  if [[ -r "$dir/tasks/demo_locked.md" ]]; then
    # A privileged runner reads the file regardless of its mode; the check
    # cannot discriminate there, so the scenario reports it instead of passing
    # silently.
    log "    note: unreadable-file assertion skipped (runner reads mode 000)"
  else
    rc=0
    bash "$SCRIPTS/run_relay.sh" --task tasks/demo_locked.md \
      --root "$dir" >"$dir/out6.txt" 2>&1 || rc=$?
    assert_eq "unreadable task path exit code" "$rc" "2" || ok=false
    assert_contains "unreadable task path named" "$dir/out6.txt" \
      "tasks/demo_locked.md" || ok=false
    [[ -e "$dir/.git_auto_review/demo_locked" ]] \
      && { log "    unreadable task path created a stem directory"; ok=false; }
  fi
  chmod 644 "$dir/tasks/demo_locked.md"
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
  # A clean tracked path the fixer will edit (so it is absent from the patch),
  # and a pre-fix rename the fixer will edit on its destination.
  (
    cd "$dir" || exit 1
    printf 'c1\nc2\n' > d/clean-tracked.txt
    printf 'r1\nr2\n' > d/old-rename.txt
    git add d/clean-tracked.txt d/old-rename.txt
    git commit --quiet -m "seed restore targets" -- d/clean-tracked.txt d/old-rename.txt
    git mv d/old-rename.txt d/new-rename.txt
  ) || ok=false
  stem="$dir/.git_auto_review/default"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false

  local captured="$outside/captured"
  mkdir -p "$captured" || { log "    cannot create $captured"; return 1; }
  local f base
  for f in d/staged-only.txt d/staged-then-edited.txt d/tracked-edit.txt \
      d/preexisting-untracked.txt d/new-untracked.txt \
      d/clean-tracked.txt d/new-rename.txt; do
    base="cap.$(printf '%s' "$f" | tr / _)"
    cp "$dir/$f" "$captured/$base" || { log "    cannot capture $f"; return 1; }
  done
  (cd "$dir" && git ls-files -s) > "$captured/index.before" || return 1

  # The fixer writes its own edits, including into one captured tracked path,
  # one clean tracked path absent from the patch, and the rename destination.
  printf 'b1\nB2\nFIXER\nb3\nb4\n' > "$dir/d/tracked-edit.txt"
  printf 'FIXER-ONLY\n' > "$dir/d/staged-only.txt"
  printf 'u1\nU2\nFIXER-EXT\n' > "$dir/d/preexisting-untracked.txt"
  printf 'CORRUPT\n' > "$dir/d/new-untracked.txt"
  printf 'fixer added\n' > "$dir/d/fixer-added.txt"
  printf 'c1\nC2-FIXER\n' > "$dir/d/clean-tracked.txt"
  printf 'r1\nR2-FIXER\n' > "$dir/d/new-rename.txt"

  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$outside/out.txt" 2>&1 || { log "    run_restore.sh exited non-zero"; ok=false; }

  for f in d/staged-only.txt d/staged-then-edited.txt d/tracked-edit.txt \
      d/preexisting-untracked.txt d/new-untracked.txt \
      d/clean-tracked.txt d/new-rename.txt; do
    base="cap.$(printf '%s' "$f" | tr / _)"
    if ! cmp -s "$dir/$f" "$captured/$base"; then
      log "    $f does not match the captured pre-fix state"
      ok=false
    fi
  done
  if [[ -e "$dir/d/old-rename.txt" ]]; then
    log "    the pre-fix rename source was recreated"
    ok=false
  fi
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

s13_restore_clean_tree() {
  local ok=true dir stem outside
  dir="$(new_sandbox restore_clean)"
  outside="$SCRATCH/restore_clean_outside"
  rm -rf "$outside"
  mkdir -p "$outside"
  (
    cd "$dir" || exit 1
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    printf 'base\n' > tracked.txt
    git add tracked.txt
    git commit --quiet -m "base"
  ) || return 1
  stem="$dir/.git_auto_review/default"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false
  # A clean pre-fix tree writes an empty patch, and restore must not fail on it.
  if [[ -s "$stem/pre-fix.patch" ]]; then
    log "    a clean tree wrote a non-empty pre-fix.patch"
    ok=false
  fi
  (cd "$dir" && git ls-files -s) > "$outside/index.before" || ok=false
  printf 'fixer\n' > "$dir/tracked.txt"
  printf 'fixer added\n' > "$dir/fixer-added.txt"
  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$outside/out.txt" 2>&1 \
    || { log "    run_restore.sh exited non-zero on a clean-tree round"; ok=false; }
  if [[ "$(cat "$dir/tracked.txt" 2>/dev/null)" != "base" ]]; then
    log "    the fixer edit on a clean tracked path survived the restore"
    ok=false
  fi
  if [[ -e "$dir/fixer-added.txt" ]]; then
    log "    the fixer-added untracked file was not deleted"
    ok=false
  fi
  (cd "$dir" && git ls-files -s) > "$outside/index.after" || ok=false
  if ! cmp -s "$outside/index.before" "$outside/index.after"; then
    log "    the index changed across restore"
    ok=false
  fi
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

# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox repository, before any worker could start.
s14_eval_runner_stage_guard() {
  local out rc
  out=$(python3 "$REPO_ROOT/tests/lib/check_stage_guard.py" \
    "$REPO_ROOT/tests/git_auto_review/evals" 2>&1) && rc=0 || rc=$?
  [[ "$rc" == 0 ]] || log "$out"
  assert_eq "tests/lib/check_stage_guard.py exit" "$rc" "0"
}


# Stage a minimal repository whose .gitignore carries the given lines and whose
# base commit carries one tracked text file. Prints nothing; fails on error.
stage_ignore_repo() {
  local dir=$1 ignores=$2
  (
    set -e
    cd "$dir"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    printf '%s' "$ignores" > .gitignore
    printf 'a1\na2\n' > tracked.txt
    git add .
    git commit --quiet -m "base"
  )
}

# The block of `diff --git` output for one path, written to stdout.
diff_block_for() {
  local diff=$1 path=$2
  awk -v want="diff --git a/$path b/$path" '
    /^diff --git / { inside = ($0 == want); next }
    inside { print }
  ' "$diff"
}

# ---------------------------------------------------------------- scenarios

s15_round_diff_path_kinds() {
  local ok=true dir stem diff block
  dir="$(new_sandbox round_diff_paths)"
  stage_ignore_repo "$dir" $'ignored/\n' || return 1
  printf 'a1\nA2\n' > "$dir/tracked.txt"
  mkdir -p "$dir/ignored"
  printf 'keep\n' > "$dir/ignored/keep.txt"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false
  stem="$dir/.git_auto_review/default"

  mkdir -p "$dir/stray/new"
  printf 'stray\n' > "$dir/stray/new/added.txt"
  printf 'fixer\n' > "$dir/ignored/fixer-added.txt"
  printf 'a1\nA2\nFIX\n' > "$dir/tracked.txt"
  printf 'relay\n' > "$stem/relay-only.txt"

  bash "$SCRIPTS/run_round_diff.sh" --stem default --round 1 --root "$dir" \
    >"$SCRATCH/round_diff_paths.out" 2>&1 || ok=false
  diff="$stem/round-r1.diff.txt"
  assert_file "round diff" "$diff" || ok=false
  assert_eq "one header per changed path" \
    "$(grep -c '^diff --git ' "$diff")" "3" || ok=false

  block="$(diff_block_for "$diff" "stray/new/added.txt")"
  [[ "$block" == *"new file mode 100644"* && "$block" == *"+stray"* ]] \
    || { log "    the untracked addition is not a whole-file addition"; ok=false; }

  block="$(diff_block_for "$diff" "ignored/fixer-added.txt")"
  [[ "$block" == *"new file mode 100644"* && "$block" == *"+fixer"* ]] \
    || { log "    the ignored addition is not a whole-file addition"; ok=false; }

  block="$(diff_block_for "$diff" "tracked.txt")"
  [[ "$block" == *"@@"* && "$block" != *"new file mode"* ]] \
    || { log "    the tracked edit is not its own hunk"; ok=false; }
  if grep -Fq 'relay-only.txt' "$diff"; then
    log "    the run's own relay file reached the round diff"
    ok=false
  fi
  $ok
}

s16_restore_removes_fixer_folders() {
  local ok=true dir stem
  dir="$(new_sandbox restore_folders)"
  stage_ignore_repo "$dir" $'ignored/\n' || return 1
  mkdir -p "$dir/pre" "$dir/ignored"
  printf 'pre\n' > "$dir/pre/keep.txt"
  printf 'keep\n' > "$dir/ignored/keep.txt"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false
  stem="$dir/.git_auto_review/default"
  printf 'r1\tbash r1.sh\n' > "$stem/ledger.txt"

  mkdir -p "$dir/new/deep" "$dir/ignored"
  printf 'fixer\n' > "$dir/new/deep/added.txt"
  printf 'fixer\n' > "$dir/ignored/fixer-added.txt"

  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$SCRATCH/restore_folders.out" 2>&1 || { log "    run_restore.sh exited non-zero"; ok=false; }

  [[ ! -e "$dir/new/deep/added.txt" && ! -e "$dir/new" ]] \
    || { log "    the fixer-added two-level folder survived the restore"; ok=false; }
  [[ ! -e "$dir/ignored/fixer-added.txt" ]] \
    || { log "    the fixer-added ignored file survived the restore"; ok=false; }
  assert_eq "the pre-existing ignored file survives" \
    "$(cat "$dir/ignored/keep.txt" 2>/dev/null)" "keep" || ok=false
  assert_eq "the pre-fix untracked file survives" \
    "$(cat "$dir/pre/keep.txt" 2>/dev/null)" "pre" || ok=false
  assert_file "pre-fix.patch survives" "$stem/pre-fix.patch" || ok=false
  assert_file "pre-fix.untracked.tar survives" "$stem/pre-fix.untracked.tar" \
    || ok=false
  assert_file "pre-fix.ignored.manifest survives" \
    "$stem/pre-fix.ignored.manifest" || ok=false
  assert_file "ledger.txt survives" "$stem/ledger.txt" || ok=false
  $ok
}

s17_round_diff_binary_paths() {
  local ok=true dir stem diff
  dir="$(new_sandbox round_diff_binary)"
  stage_ignore_repo "$dir" $'ignored/\n' || return 1
  printf '\376\377' > "$dir/tracked.bin"
  (cd "$dir" && git add tracked.bin && git commit --quiet -m "binary base") \
    || return 1
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false
  stem="$dir/.git_auto_review/default"

  mkdir -p "$dir/ignored"
  printf '\377\376' > "$dir/ignored/added.bin"
  printf '\375\376' > "$dir/untracked.bin"
  printf '\377\376\375' > "$dir/tracked.bin"

  bash "$SCRIPTS/run_round_diff.sh" --stem default --round 1 --root "$dir" \
    >"$SCRATCH/round_diff_binary.out" 2>&1 || ok=false
  diff="$stem/round-r1.diff.txt"
  assert_file "binary round diff" "$diff" || ok=false
  assert_contains "ignored binary path-only hunk" "$diff" \
    "Binary files /dev/null and b/ignored/added.bin differ" || ok=false
  assert_contains "untracked binary path-only hunk" "$diff" \
    "Binary files /dev/null and b/untracked.bin differ" || ok=false
  assert_contains "tracked binary path-only hunk" "$diff" \
    "Binary files a/tracked.bin and b/tracked.bin differ" || ok=false
  if ! python3 -c 'import sys; data = open(sys.argv[1], "rb").read(); data.decode("utf-8"); sys.exit(1 if b"\x00" in data else 0)' "$diff"; then
    log "    the round diff is not valid UTF-8 without NUL bytes"
    ok=false
  fi
  $ok
}

s18_snapshot_skips_run_output_trees() {
  local ok=true dir stem manifest list
  dir="$(new_sandbox snapshot_run_output)"
  stage_ignore_repo "$dir" $'ignored/\ntests/**/workspace/\n' || return 1
  mkdir -p "$dir/ignored" "$dir/tests/demo/workspace"
  printf 'keep\n' > "$dir/ignored/keep.txt"
  printf 'run output\n' > "$dir/tests/demo/workspace/run.txt"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || ok=false
  stem="$dir/.git_auto_review/default"
  manifest="$stem/pre-fix.ignored.manifest"
  assert_file "ignored manifest" "$manifest" || ok=false
  list="$SCRATCH/snapshot_run_output.manifest.txt"
  tr '\0' '\n' < "$manifest" > "$list"
  assert_contains "the normal ignored path is listed" "$list" "ignored/keep.txt" \
    || ok=false
  if grep -Fq 'tests/demo/workspace' "$list"; then
    log "    the run-output tree reached the ignored manifest"
    ok=false
  fi
  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$SCRATCH/snapshot_run_output.out" 2>&1 || { log "    run_restore.sh exited non-zero"; ok=false; }
  assert_eq "the run-output tree file is untouched" \
    "$(cat "$dir/tests/demo/workspace/run.txt" 2>/dev/null)" "run output" \
    || ok=false
  $ok
}

s19_ledger_bytecode_off() {
  local ok=true dir out status
  dir="$(new_sandbox ledger_bytecode)"
  (
    set -e
    cd "$dir"
    git init --quiet --initial-branch=main
    git config user.name "Harness"
    git config user.email "harness@example.test"
    cat > report.py <<'PY'
def total(items):
    return sum(items)
PY
    cat > check.py <<'PY'
from report import total

assert total([1, 2, 3]) == 6, "total must sum the items"
PY
    git add report.py check.py
    git commit --quiet -m "base"
  ) || return 1
  printf 'check.py\tpython3 check.py\n' > "$dir/ledger.txt"
  # Run the ledger with the caller's bytecode settings removed, so the result
  # rests on run_ledger.sh's own export alone: an agent harness that already
  # exports PYTHONDONTWRITEBYTECODE, or a PYTHONPYCACHEPREFIX that moves the
  # cache out of the sandbox, would otherwise pass this scenario against a
  # ledger that never turns bytecode writing off.
  env -u PYTHONDONTWRITEBYTECODE -u PYTHONPYCACHEPREFIX \
    bash "$SCRIPTS/run_ledger.sh" --ledger "$dir/ledger.txt" --cwd "$dir" \
    >"$SCRATCH/ledger_bytecode.out" 2>&1 || ok=false
  assert_contains "the plain python command passes" "$SCRATCH/ledger_bytecode.out" \
    "line 1: PASS" || ok=false
  status="$(cd "$dir" && git status --porcelain --untracked-files=all)"
  if printf '%s\n' "$status" | grep -Fq '__pycache__'; then
    log "    the ledger left a __pycache__ path in git status"
    ok=false
  fi
  out="$(find "$dir" -name __pycache__ -print)"
  [[ -z "$out" ]] || { log "    a __pycache__ directory exists: $out"; ok=false; }
  $ok
}

s20_newline_untracked_path() {
  local ok=true dir stem newline_name
  dir="$(new_sandbox snapshot_newline)"
  stage_ignore_repo "$dir" $'ignored/\n' || return 1
  newline_name=$'weird\nname.txt'
  printf 'n1\nn2\n' > "$dir/$newline_name"
  bash "$SCRIPTS/run_relay.sh" --root "$dir" >/dev/null 2>&1 || ok=false
  bash "$SCRIPTS/run_snapshot.sh" --stem default --root "$dir" >/dev/null 2>&1 \
    || { log "    run_snapshot.sh failed on a newline-named path"; ok=false; }
  stem="$dir/.git_auto_review/default"
  mkdir -p "$dir/extract"
  tar -xf "$stem/pre-fix.untracked.tar" -C "$dir/extract" 2>/dev/null \
    || { log "    cannot unpack the snapshot archive"; ok=false; }
  assert_file "the newline-named path is one archive member" \
    "$dir/extract/$newline_name" || ok=false

  printf 'fixer\n' > "$dir/tracked.txt"
  printf 'fixer added\n' > "$dir/fixer-added.txt"
  bash "$SCRIPTS/run_restore.sh" --stem default --root "$dir" \
    >"$SCRATCH/snapshot_newline.out" 2>&1 || { log "    run_restore.sh failed"; ok=false; }
  assert_file "the restore puts the newline-named path back" \
    "$dir/$newline_name" || ok=false
  assert_eq "the tracked path returns to HEAD" \
    "$(cat "$dir/tracked.txt")" "a1
a2" || ok=false
  [[ ! -e "$dir/fixer-added.txt" ]] \
    || { log "    the fixer-added file survived"; ok=false; }
  $ok
}

# stage_gate_scope_case <dir> <section-body-file> — a sandbox whose staged
# relay report carries the given `## Bugs it may introduce` body and a verdict
# block naming both defect paths, so only the section body varies.
stage_gate_scope_case() {
  local dir=$1 body=$2 sha
  mkdir -p "$dir/repo/.git_auto_review/default"
  (
    cd "$dir/repo" || exit 1
    git init --quiet --initial-branch=main
    git config user.name "Repro"
    git config user.email "repro@example.test"
    printf 'def total(items):\n    return sum(items) / 0\n' > report.py
    git add report.py
    git commit --quiet -m "fixture base"
  ) || return 1
  sha="$(git -C "$dir/repo" rev-parse HEAD)"
  printf '%s\n' "$sha" > "$dir/.base.sha"
  printf '%s\n' "$sha" > "$dir/.head.before"
  (cd "$dir/repo" && git for-each-ref) > "$dir/.refs.before"
  (cd "$dir/repo" && printf '%s\n' "$(git worktree list --porcelain)") \
    > "$dir/.worktrees.before"
  cp "$dir/repo/report.py" "$dir/.report.before"
  {
    printf 'Reviewed HEAD on main against origin/main at %s.\n\n' "$sha"
    printf '## What the changes do and implement\n\nA branch defect.\n\n'
    printf '## What it retires\n\nNothing.\n\n'
    printf '## What of the existing workflow changes\n\nNothing.\n\n'
    printf '## Bugs it may introduce\n\n'
    cat "$body"
    printf '\n## What should be fixed though it is not a clear bug\n\nNone.\n\n'
    printf '## Decisions the implementer must make before fixing\n\nNone.\n\n'
    printf '## Can it be structurally merged as it is\n\nYes.\n\n'
    printf '# auto_gate_git verdict\n\n## Findings\n\n'
    printf 'id: 1\nheading: Bugs it may introduce\nlabel: verified\n'
    printf 'location: report.py:4\nlane: working-tree lane\ntag: none\n\n'
    printf 'id: 2\nheading: Bugs it may introduce\nlabel: verified\n'
    printf 'location: report.py:3\nlane: working-tree lane\ntag: none\n'
  } > "$dir/repo/.git_auto_review/default/report.txt"
}

s21_grade_section_scope() {
  local ok=true dir committed uncommitted
  local label_committed="the committed defect is reported under Bugs it may introduce"
  local label_uncommitted="the uncommitted defect is reported under Bugs it may introduce"
  local work="$SCRATCH/grade_section_scope"
  rm -rf "$work"
  mkdir -p "$work"

  printf 'The defect paths are named only in the verdict.\n' > "$work/off_body.txt"
  dir="$work/off_body"
  stage_gate_scope_case "$dir" "$work/off_body.txt" || return 1
  RESPONSE_FILE="" bash "$GRADE_SCRIPT" gate_reviews_branch_and_worktree \
    "$dir/repo" "$dir" > "$dir/grade.out" 2>&1
  committed="$(grep -F -- "$label_committed" "$dir/grade.out" || true)"
  uncommitted="$(grep -F -- "$label_uncommitted" "$dir/grade.out" || true)"
  [[ "$committed" == *FAIL* ]] \
    || { log "    the committed verdict-only check did not fail"; ok=false; }
  [[ "$uncommitted" == *FAIL* ]] \
    || { log "    the uncommitted verdict-only check did not fail"; ok=false; }

  {
    printf '**report.py:4** — the committed defect divides by zero.\n'
    printf '**report.py:3** — the uncommitted defect divides by zero.\n'
  } > "$work/in_body.txt"
  dir="$work/in_body"
  stage_gate_scope_case "$dir" "$work/in_body.txt" || return 1
  RESPONSE_FILE="" bash "$GRADE_SCRIPT" gate_reviews_branch_and_worktree \
    "$dir/repo" "$dir" > "$dir/grade.out" 2>&1
  committed="$(grep -F -- "$label_committed" "$dir/grade.out" || true)"
  uncommitted="$(grep -F -- "$label_uncommitted" "$dir/grade.out" || true)"
  [[ "$committed" == *ok* ]] \
    || { log "    the committed in-body check did not pass"; ok=false; }
  [[ "$uncommitted" == *ok* ]] \
    || { log "    the uncommitted in-body check did not pass"; ok=false; }
  $ok
}

s22_grade_ledger_per_finding() {
  local ok=true dir line
  local label="the ledger holds one reproduction per finding"
  local work="$SCRATCH/grade_ledger_per_finding"
  rm -rf "$work"
  mkdir -p "$work"

  stage_ledger_case() {
    local case_dir=$1
    mkdir -p "$case_dir/repo/.git_auto_review/default"
    printf 'def total(items):\n    return sum(items)\n' > "$case_dir/repo/report.py"
    printf '# Ledger notes\n\nThe regression ledger stores one reproduction per finding in `ledger.txt`.\n' \
      > "$case_dir/repo/notes.md"
    printf 'no qualifying finding remains\n' > "$case_dir/response.txt"
    : > "$case_dir/repo/.git_auto_review/default/ledger.txt"
    {
      printf '# auto_fixer_git record\n\n## Writes\n\n'
      printf 'path: repro/one.sh\nfinding: 1\nkind: reproduction\n\n'
      printf 'path: repro/two.sh\nfinding: 2\nkind: reproduction\n\n'
      printf '## Ledger\n\n'
      printf 'line: repro/one.sh\tbash repro/one.sh\n'
      printf 'line: repro/two.sh\tbash repro/two.sh\n'
    } > "$case_dir/repo/.git_auto_review/default/fixer-r1.txt"
  }

  grade_ledger_case() {
    local case_dir=$1
    RESPONSE_FILE="$case_dir/response.txt" \
      bash "$GRADE_SCRIPT" fixes_inferred_and_should_fix_findings \
      "$case_dir/repo" "$case_dir" > "$case_dir/grade.out" 2>&1
    grep -F -- "$label" "$case_dir/grade.out" || true
  }

  dir="$work/per_finding"
  stage_ledger_case "$dir"
  {
    printf 'repro/one.sh\tbash repro/one.sh\n'
    printf 'repro/two.sh\tbash repro/two.sh\n'
  } > "$dir/repo/.git_auto_review/default/ledger.txt"
  line="$(grade_ledger_case "$dir")"
  [[ "$line" == *ok* ]] \
    || { log "    one line per finding did not pass: $line"; ok=false; }

  dir="$work/both_for_one"
  stage_ledger_case "$dir"
  {
    printf 'repro/one.sh\tbash repro/one.sh\n'
    printf 'repro/one.sh\tbash repro/one.sh\n'
  } > "$dir/repo/.git_auto_review/default/ledger.txt"
  line="$(grade_ledger_case "$dir")"
  [[ "$line" == *FAIL* ]] \
    || { log "    two lines for one finding did not fail: $line"; ok=false; }

  dir="$work/empty"
  stage_ledger_case "$dir"
  line="$(grade_ledger_case "$dir")"
  [[ "$line" == *FAIL* ]] \
    || { log "    the empty ledger did not report a clean failure: $line"; ok=false; }
  if grep -Fq "arithmetic syntax error" "$dir/grade.out"; then
    log "    the empty-ledger path raised an arithmetic syntax error"
    ok=false
  fi
  $ok
}

s23_eval_docs_inventory() {
  local ok=true evals_readme harness_readme runbook
  evals_readme="$REPO_ROOT/tests/git_auto_review/evals/README.md"
  harness_readme="$REPO_ROOT/tests/git_auto_review/README.md"
  runbook="$REPO_ROOT/tests/git_auto_review/RUNBOOK.md"

  assert_contains "the named-target decline has a signal row" "$evals_readme" \
    '| `declines_on_named_other_branch` |' || ok=false
  assert_contains "the branch-target sentence names the decline eval" \
    "$harness_readme" '`declines_on_named_other_branch`' || ok=false
  assert_contains "the triage row names its class" "$evals_readme" \
    '| `triage_reports_status_and_reason` |' || ok=false
  if ! grep -F -- '| `triage_reports_status_and_reason` |' "$evals_readme" \
    | grep -Fq 'triage-not-approved'; then
    log "    the triage signal row does not name triage-not-approved"
    ok=false
  fi
  assert_contains "the runbook records the deployed root in ~ form" "$runbook" \
    '`deployed_root:` line' || ok=false
  assert_contains "the runbook names the tilde deployed root" "$runbook" \
    '`~/.claude/skills/git_review`' || ok=false
  if grep -nE '/Users/[^/]+/' "$runbook"; then
    log "    the runbook records an absolute home path"
    ok=false
  fi
  $ok
}

scenario s1 "new skill and agents exist with aligned frontmatter" s1_files_and_frontmatter
scenario s2 "new pseudo-XML artefacts lint clean" s2_pseudo_xml_lints
scenario s3 "lane classification is stated once and read by the gate" s3_lane_classification_single_source
scenario s4 "convergence states the four labels and the stop conditions once" s4_convergence_labels_single_source
scenario s5 "the carry-over blocks and path resolution exist" s5_carryover_blocks
scenario s6 "run_ledger.sh honours the ledger exit and reporting contract" s6_ledger_contract
scenario s7 "run_relay.sh initialises the relay and preserves marked pairs" s7_relay_init_and_preseed
scenario s8 "run_snapshot.sh writes the pre-fix pair and the once-only baseline" s8_snapshot_and_baseline
scenario s9 "run_restore.sh reproduces the captured worktree, index untouched" s9_restore_reproduces_captured_state
scenario s10 "run_restore.sh reports the state it cannot reproduce" s10_restore_reports_inability
scenario s11 "the Makefile EXCLUDE prune covers a repository-root run" s11_makefile_exclude_prune
scenario s12 "the shared isolation allowlist names the harness prefix" s12_isolation_allowlist
scenario s13 "run_restore.sh reproduces a clean pre-fix tree" s13_restore_clean_tree
scenario s14 "the eval runner stops on a failed or empty stage" s14_eval_runner_stage_guard
scenario s15 "run_round_diff.sh reports each changed path kind once" s15_round_diff_path_kinds
scenario s16 "run_restore.sh removes the folders the fixer created" s16_restore_removes_fixer_folders
scenario s17 "run_round_diff.sh carries binary paths as path-only hunks" s17_round_diff_binary_paths
scenario s18 "run_snapshot.sh skips the harness run-output trees" s18_snapshot_skips_run_output_trees
scenario s19 "run_ledger.sh runs every command with bytecode writing off" s19_ledger_bytecode_off
scenario s20 "snapshot and restore survive a newline in an untracked name" s20_newline_untracked_path
scenario s21 "the branch-and-worktree grader scopes defects to their section" s21_grade_section_scope
scenario s22 "the ledger grader keys its check per finding" s22_grade_ledger_per_finding
scenario s23 "the eval docs and runbook enumerate the measured behaviour" s23_eval_docs_inventory

log ""
log "================================================================"
log "  $SCENARIOS scenarios — $PASS pass, $FAIL fail"
log "================================================================"

if (( FAIL > 0 )); then
  exit 1
fi
exit 0
