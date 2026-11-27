#!/usr/bin/env bash
# update_features script tests - deterministic checks for the shipped helper
# and for the skill's task-system independence.
#
# Each scenario prints PASS or FAIL and the run exits non-zero on any failure.
# Scratch sandboxes live under script_tests/scratch/, which is gitignored.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL="$REPO_ROOT/plugins/ai_dev/skills/update_features"
SCAN="$SKILL/scripts/scan_features_sources.sh"
FIXTURE="$SCRIPT_DIR/../evals/fixtures/ledger-fixture"
SCRATCH="$SCRIPT_DIR/scratch"

PASS=0
FAIL=0
FAILED=()

ok() { PASS=$((PASS + 1)); printf 'PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED+=("$1"); printf 'FAIL  %s\n' "$1"; }

fresh() {
    local id=$1
    local dir="$SCRATCH/$id"
    rm -rf "$dir"
    mkdir -p "$dir"
    printf '%s' "$dir"
}

# t1: the scan names the fixture's manifest, entry point, docs, and test layout.
t1_scan_names_behaviour_surfaces() {
    local dir out
    dir=$(fresh t1)
    out="$dir/scan.txt"
    bash "$SCAN" --root "$FIXTURE" --out "$out" >/dev/null || { bad "t1 scan exits 0"; return; }
    local ok_all=true
    grep -qx 'package.json' <(sed -n '/## Manifests and toolchain files/,/^$/p' "$out") || ok_all=false
    grep -q '^src/cli\.js$' <(sed -n '/## Executable entry points/,/^$/p' "$out") || ok_all=false
    grep -q '^README\.md$' <(sed -n '/## Behaviour-describing docs/,/^$/p' "$out") || ok_all=false
    grep -q '^test/$' <(sed -n '/## Test layout/,/^$/p' "$out") || ok_all=false
    grep -q 'ledger-fixture' "$out" || ok_all=false
    if $ok_all; then
        ok "t1 scan names manifest, entry point, docs, and test layout"
    else
        bad "t1 scan names manifest, entry point, docs, and test layout"
    fi
}

# t2: the declared-target markers reach the scan, which feeds the not-yet-built boundary.
t2_scan_reports_declared_targets() {
    local dir out
    dir=$(fresh t2)
    out="$dir/scan.txt"
    bash "$SCAN" --root "$FIXTURE" --out "$out" >/dev/null || { bad "t2 scan exits 0"; return; }
    if grep -q 'TODO: add a `--shout` flag' "$out"; then
        ok "t2 scan reports a declared, unbuilt target"
    else
        bad "t2 scan reports a declared, unbuilt target"
    fi
}

# t3: the scan is deterministic - two runs over an unchanged tree agree
# everywhere except the generated-at stamp.
t3_scan_is_deterministic() {
    local dir a b
    dir=$(fresh t3)
    a="$dir/a.txt"; b="$dir/b.txt"
    bash "$SCAN" --root "$FIXTURE" --out "$a" >/dev/null || { bad "t3 first scan exits 0"; return; }
    bash "$SCAN" --root "$FIXTURE" --out "$b" >/dev/null || { bad "t3 second scan exits 0"; return; }
    if diff <(grep -v '^generated: ' "$a") <(grep -v '^generated: ' "$b") >/dev/null; then
        ok "t3 scan is deterministic across runs"
    else
        bad "t3 scan is deterministic across runs"
    fi
}

# t4: the scan works outside a git work tree, so the skill needs no VCS.
t4_scan_works_outside_git() {
    local dir out
    dir=$(fresh t4)
    out="$dir/scan.txt"
    ( cd "$dir" && bash "$SCAN" --root "$FIXTURE" --out "$out" ) >/dev/null || { bad "t4 scan outside git exits 0"; return; }
    if grep -q '^src/cli\.js$' <(sed -n '/## Executable entry points/,/^$/p' "$out"); then
        ok "t4 scan works outside a git work tree"
    else
        bad "t4 scan works outside a git work tree"
    fi
}

# t5: the skill carries no task-system dependency, so it runs where tasks/ does not exist.
t5_skill_has_no_task_dependency() {
    local hits
    hits=$(grep -rn 'tasks/' "$SKILL" 2>/dev/null | grep -v 'requires no' || true)
    if [[ -z "$hits" ]]; then
        ok "t5 skill carries no tasks/ dependency"
    else
        printf '%s\n' "$hits" >&2
        bad "t5 skill carries no tasks/ dependency"
    fi
}

# t6: the task lifecycle requires no FEATURES.md - its consult stays conditional
# and the backlog lints with the file absent.
t6_task_lifecycle_does_not_require_features() {
    local task_skill="$REPO_ROOT/plugins/ai_dev/skills/task/SKILL.md"
    local ok_all=true
    grep -qF 'When `FEATURES.md` and/or `ARCHITECTURE.md` exist at the project root' "$task_skill" || ok_all=false
    if grep -nE 'FEATURES\.md[^.]{0,80}(is required|must exist)|requires? `FEATURES\.md`' "$task_skill"; then
        ok_all=false
    fi
    [[ -e "$REPO_ROOT/FEATURES.md" ]] && ok_all=false
    ( cd "$REPO_ROOT" && python3 plugins/ai_dev/skills/task/scripts/lint.py --quiet >/dev/null 2>&1 ) || ok_all=false
    if $ok_all; then
        ok "t6 task lifecycle requires no FEATURES.md"
    else
        bad "t6 task lifecycle requires no FEATURES.md"
    fi
}

# t7: the skill ships its helper under scripts/ and its body cites the helper path.
t7_skill_ships_helper() {
    local ok_all=true
    [[ -x "$SCAN" ]] || ok_all=false
    grep -qF 'scripts/scan_features_sources.sh' "$SKILL/SKILL.md" || ok_all=false
    if $ok_all; then
        ok "t7 skill ships scripts/scan_features_sources.sh and cites it"
    else
        bad "t7 skill ships scripts/scan_features_sources.sh and cites it"
    fi
}

t1_scan_names_behaviour_surfaces
t2_scan_reports_declared_targets
t3_scan_is_deterministic
t4_scan_works_outside_git
t5_skill_has_no_task_dependency
t6_task_lifecycle_does_not_require_features
t7_skill_ships_helper

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
if [[ $FAIL -gt 0 ]]; then
    printf 'failed: %s\n' "${FAILED[*]}"
    exit 1
fi
exit 0
