#!/usr/bin/env bash
# Bundled-script unit tests for the git_refresh skill.
# s11 and s12 check the eval harness: the runner's stage() stops on a failed
# or empty stage, and eval 3's grade reads the gated order from the helper log.
# shellcheck disable=SC2329

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/git_refresh"
REFRESH="$SKILL_DIR/scripts/refresh_repo.sh"
EVALS_DIR="$REPO_ROOT/tests/git_refresh/evals"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/layer1.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

fresh_repo() {
    local id=$1
    local default_branch=$2
    local root="$SCRATCH/$id"
    local origin="$root/origin.git"
    local repo="$root/repo"

    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --bare --initial-branch="$default_branch" "$origin"
    git clone --quiet "$origin" "$repo"
    (
        cd "$repo"
        git config user.email "harness@example.com"
        git config user.name "Harness"
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
        git push --quiet -u origin "$default_branch"
        git remote set-head origin "$default_branch"
    ) || return 1
    printf '%s' "$repo"
}

upstream_commit() {
    local repo=$1
    local branch=$2
    local file=$3
    local content=$4
    local message=$5
    local work

    work="$(mktemp -d)"
    git clone --quiet "$(cd "$repo" && git config --get remote.origin.url)" "$work/repo"
    (
        cd "$work/repo" || exit 1
        git config user.email "harness@example.com"
        git config user.name "Harness"
        git checkout --quiet "$branch"
        printf '%s\n' "$content" > "$file"
        git add "$file"
        git commit --quiet -m "$message"
        git push --quiet origin "$branch"
    )
    rm -rf "$work"
}

run_refresh() {
    local repo=$1
    shift
    local out rc

    out=$(cd "$repo" && "$REFRESH" "$@" 2>&1) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

assert_eq() {
    local label=$1 actual=$2 expected=$3
    if [[ "$actual" == "$expected" ]]; then
        return 0
    fi
    log "    [diff: $label]"
    log "      expected: $(printf '%q' "$expected")"
    log "      actual:   $(printf '%q' "$actual")"
    return 1
}

assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi
    log "    [missing substring: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

assert_branch_exists() {
    local repo=$1 branch=$2
    if (cd "$repo" && git show-ref --verify --quiet "refs/heads/$branch"); then
        return 0
    fi
    log "    [missing branch: $branch]"
    return 1
}

assert_branch_missing() {
    local repo=$1 branch=$2
    if (cd "$repo" && ! git show-ref --verify --quiet "refs/heads/$branch"); then
        return 0
    fi
    log "    [unexpected branch present: $branch]"
    return 1
}

scenario() {
    local id=$1 desc=$2 body=$3
    log ""
    log "=== $id  $desc ==="
    if "$body"; then
        PASS=$((PASS+1))
        log "  PASS"
    else
        FAIL=$((FAIL+1))
        FAILED_IDS+=("$id")
        log "  FAIL"
    fi
}

s1_master_default_refreshes_and_deletes_merged() {
    local repo ret rc out branch
    repo=$(fresh_repo s1 master) || return 1
    (
        cd "$repo"
        git checkout --quiet -b merged-topic
        printf 'merged\n' > merged.txt
        git add merged.txt
        git commit --quiet -m "merged topic"
        git checkout --quiet master
        git merge --quiet --ff-only merged-topic
        git push --quiet origin master
        git checkout --quiet merged-topic
    ) || return 1
    upstream_commit "$repo" master upstream.txt upstream "upstream"

    ret=$(run_refresh "$repo")
    rc=${ret%%|*}
    out=${ret#*|}
    branch=$(cd "$repo" && git symbolic-ref --quiet --short HEAD)

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "current branch" "$branch" "master" || ok=false
    [[ -f "$repo/upstream.txt" ]] || { log "    [upstream file missing]"; ok=false; }
    assert_branch_missing "$repo" merged-topic || ok=false
    assert_contains "default branch reported" "$out" "Default branch: master" || ok=false
    assert_contains "fast-forward reported" "$out" "Fast-forward: master advanced" || ok=false
    assert_contains "merged branch deleted" "$out" "Deleted merged branch: merged-topic" || ok=false
    $ok
}

s2_diverged_upstream_left_unchanged() {
    local repo local_head ret rc out head_after
    repo=$(fresh_repo s2 main) || return 1
    (
        cd "$repo"
        printf 'local\n' > local.txt
        git add local.txt
        git commit --quiet -m "local main work"
        local_head=$(git rev-parse HEAD)
        printf '%s\n' "$local_head" > "$SCRATCH/s2/local-head"
    ) || return 1
    upstream_commit "$repo" main upstream.txt upstream "upstream"

    local_head=$(cat "$SCRATCH/s2/local-head")
    ret=$(run_refresh "$repo")
    rc=${ret%%|*}
    out=${ret#*|}
    head_after=$(cd "$repo" && git rev-parse HEAD)

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "HEAD unchanged" "$head_after" "$local_head" || ok=false
    [[ ! -f "$repo/upstream.txt" ]] || { log "    [upstream file should not be merged]"; ok=false; }
    assert_contains "divergence reported" "$out" "have diverged; no merge or rebase was performed" || ok=false
    $ok
}

s3_default_leaves_unique_gone_branch_and_offers() {
    local repo ret rc out
    repo=$(fresh_repo s3 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b merged-topic
        printf 'merged\n' > merged.txt
        git add merged.txt
        git commit --quiet -m "merged topic"
        git checkout --quiet main
        git merge --quiet --ff-only merged-topic
        git checkout --quiet -b gone-unique
        printf 'unique\n' > unique.txt
        git add unique.txt
        git commit --quiet -m "unique local work"
        git push --quiet -u origin gone-unique
        git push --quiet origin --delete gone-unique
    ) || return 1

    ret=$(run_refresh "$repo")
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_branch_missing "$repo" merged-topic || ok=false
    assert_branch_exists "$repo" gone-unique || ok=false
    assert_contains "follow-up question" "$out" "Follow-up question: handle gated branch cleanup now?" || ok=false
    assert_contains "gone branch named" "$out" "gone-unique" || ok=false
    assert_contains "unique commit shown" "$out" "unique local work" || ok=false
    $ok
}

s4_no_gated_candidates_reports_nothing_further() {
    local repo ret rc out
    repo=$(fresh_repo s4 main) || return 1

    ret=$(run_refresh "$repo")
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "nothing further" "$out" "Gated cleanup: nothing further remains." || ok=false
    assert_branch_exists "$repo" main || ok=false
    $ok
}

s5_dirty_worktree_blocks_switch_without_hiding_changes() {
    local repo ret rc out branch status content
    repo=$(fresh_repo s5 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b work-in-progress
        printf 'dirty\n' > dirty.txt
    ) || return 1

    ret=$(run_refresh "$repo")
    rc=${ret%%|*}
    out=${ret#*|}
    branch=$(cd "$repo" && git symbolic-ref --quiet --short HEAD)
    status=$(cd "$repo" && git status --short)
    content=$(cat "$repo/dirty.txt")

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_eq "current branch unchanged" "$branch" "work-in-progress" || ok=false
    assert_eq "dirty content preserved" "$content" "dirty" || ok=false
    assert_contains "status still dirty" "$status" "dirty.txt" || ok=false
    assert_contains "dirty reported" "$out" "Dirty worktree" || ok=false
    assert_contains "switch skipped" "$out" "Skipped switch to main" || ok=false
    $ok
}

s6_prune_gone_deletes_safe_branch_with_branch_d() {
    local repo ret rc out
    repo=$(fresh_repo s6 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b gone-merged
        printf 'gone merged\n' > gone-merged.txt
        git add gone-merged.txt
        git commit --quiet -m "gone merged"
        git push --quiet -u origin gone-merged
        git checkout --quiet main
        git merge --quiet --ff-only gone-merged
        git push --quiet origin main
        git push --quiet origin --delete gone-merged
    ) || return 1

    ret=$(run_refresh "$repo" --prune-gone gone-merged)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_branch_missing "$repo" gone-merged || ok=false
    assert_contains "pruned safe branch" "$out" "Pruned upstream-gone branch with no unique commits: gone-merged" || ok=false
    $ok
}

s7_prune_gone_leaves_unique_branch() {
    local repo ret rc out
    repo=$(fresh_repo s7 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b gone-unique
        printf 'unique\n' > unique.txt
        git add unique.txt
        git commit --quiet -m "unique local work"
        git push --quiet -u origin gone-unique
        git push --quiet origin --delete gone-unique
        git checkout --quiet main
    ) || return 1

    ret=$(run_refresh "$repo" --prune-gone gone-unique)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_branch_exists "$repo" gone-unique || ok=false
    assert_contains "force confirmation named" "$out" "Force-delete confirmation required for gone-unique" || ok=false
    assert_contains "commit shown" "$out" "unique local work" || ok=false
    $ok
}

s8_force_delete_requires_confirmation() {
    local repo ret rc out
    repo=$(fresh_repo s8 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b gone-unique
        printf 'unique\n' > unique.txt
        git add unique.txt
        git commit --quiet -m "unique local work"
        git checkout --quiet main
    ) || return 1

    ret=$(run_refresh "$repo" --force-delete gone-unique)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_branch_exists "$repo" gone-unique || ok=false
    assert_contains "commits shown first" "$out" "Commits that would be lost:" || ok=false
    assert_contains "confirmation required" "$out" "explicit confirmation required" || ok=false
    $ok
}

s9_force_delete_after_explicit_confirmation() {
    local repo ret rc out
    repo=$(fresh_repo s9 main) || return 1
    (
        cd "$repo"
        git checkout --quiet -b gone-unique
        printf 'unique\n' > unique.txt
        git add unique.txt
        git commit --quiet -m "unique local work"
        git checkout --quiet main
    ) || return 1

    ret=$(run_refresh "$repo" --force-delete gone-unique --confirm-force-delete gone-unique)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_branch_missing "$repo" gone-unique || ok=false
    assert_contains "force deleted" "$out" "Force-deleted branch after explicit confirmation: gone-unique" || ok=false
    $ok
}

s10_help_and_unknown_argument() {
    local repo ret rc out bad_rc
    repo=$(fresh_repo s10 main) || return 1

    ret=$(run_refresh "$repo" --help)
    rc=${ret%%|*}
    out=${ret#*|}
    (cd "$repo" && "$REFRESH" --bogus >/dev/null 2>&1) && bad_rc=0 || bad_rc=$?

    local ok=true
    assert_eq "help exit" "$rc" "0" || ok=false
    assert_contains "usage" "$out" "Usage:" || ok=false
    assert_eq "unknown arg exit" "$bad_rc" "1" || ok=false
    $ok
}

# --- Eval harness ------------------------------------------------------------

# The eval runner's stage() raises on a stage.sh that fails, and on one that
# exits 0 without naming a sandbox repository, because pathlib.Path("") is the
# current directory and the worker would otherwise start in the checkout.
s11_eval_runner_stage_failure_raises() {
    local out rc
    out=$(python3 "$REPO_ROOT/tests/lib/check_stage_guard.py" "$EVALS_DIR" 2>&1) && rc=0 || rc=$?
    [[ "$rc" == 0 ]] || log "$out"
    assert_eq "tests/lib/check_stage_guard.py exit" "$rc" "0"
}

# Eval 3's grade proves the gated order from the runner's helper log. The
# default run alone already deletes gone-merged, so the repository state passes
# either way, and only the log the shim writes tells the two runs apart: after
# the default run alone the grade fails, and after the --prune-gone follow-up
# it passes.
s12_eval3_grade_reads_order_from_shimmed_helper_log() {
    local root target repo shim out rc ok=true sandbox_repo
    # stage.sh's eval below also assigns these; local keeps them out of the
    # other scenarios.
    # shellcheck disable=SC2034
    local skill_path prompt
    root="$SCRATCH/s12"
    target="$root/target"
    rm -rf "$root"
    mkdir -p "$root"
    eval "$(bash "$EVALS_DIR/stage.sh" 3 "$target" 2>/dev/null)" || return 1
    repo="$sandbox_repo"
    target="$(cd "$repo/.." && pwd -P)"
    shim=$(python3 - "$EVALS_DIR" "$SKILL_DIR" "$root/home" "$target" 2>&1 <<'PY'
import pathlib
import shutil
import sys
import types

sys.path.insert(0, sys.argv[1])
import run  # noqa: E402

skill = pathlib.Path(sys.argv[3]) / "skills" / "git_refresh"
shutil.copytree(sys.argv[2], skill)
deploy = types.SimpleNamespace(
    path_map={"git_refresh": skill / "SKILL.md"},
    scratch_home=pathlib.Path(sys.argv[3]),
)
run.shim_deployed_scripts(deploy, pathlib.Path(sys.argv[4]))
print(skill / "scripts" / "refresh_repo.sh")
PY
) || { log "    [shim setup failed: $shim]"; return 1; }

    (cd "$repo" && bash "$shim" >/dev/null 2>&1)
    out=$(bash "$EVALS_DIR/grade.sh" 3 "$repo" 2>&1) && rc=0 || rc=$?
    assert_eq "grade after the default run alone" "$rc" "1" || ok=false
    assert_contains "the missing follow-up fails" "$out" \
        "FAIL  the helper log records a refresh_repo.sh --prune-gone call after that default run" || ok=false
    assert_contains "the default run still passes" "$out" \
        "PASS  the helper log records a default run of refresh_repo.sh with no arguments" || ok=false

    (cd "$repo" && bash "$shim" --prune-gone >/dev/null 2>&1)
    out=$(bash "$EVALS_DIR/grade.sh" 3 "$repo" 2>&1) && rc=0 || rc=$?
    assert_eq "grade after the --prune-gone follow-up" "$rc" "0" || ok=false
    assert_eq "the shim logged both calls in order" "$(cat "$target/script_calls.log")" \
        "$(printf 'refresh_repo.sh \nrefresh_repo.sh --prune-gone')" || ok=false
    $ok
}

scenario s1  "master default: switch, fast-forward, delete merged branch" s1_master_default_refreshes_and_deletes_merged
scenario s2  "diverged upstream: report and leave unchanged"              s2_diverged_upstream_left_unchanged
scenario s3  "default run: delete merged, leave unique gone, offer"       s3_default_leaves_unique_gone_branch_and_offers
scenario s4  "default run: no gated candidates"                           s4_no_gated_candidates_reports_nothing_further
scenario s5  "dirty worktree: skip blocked switch without stash"          s5_dirty_worktree_blocks_switch_without_hiding_changes
scenario s6  "gated prune: delete gone branch with no unique commits"     s6_prune_gone_deletes_safe_branch_with_branch_d
scenario s7  "gated prune: leave gone branch with unique commits"         s7_prune_gone_leaves_unique_branch
scenario s8  "force-delete: require explicit confirmation"                s8_force_delete_requires_confirmation
scenario s9  "force-delete: delete after exact confirmation"              s9_force_delete_after_explicit_confirmation
scenario s10 "flags: help and unknown argument handling"                  s10_help_and_unknown_argument
scenario s11 "eval runner: a failed or empty stage raises before any worker" s11_eval_runner_stage_failure_raises
scenario s12 "eval 3 grade: the shimmed helper log proves the gated order" s12_eval3_grade_reads_order_from_shimmed_helper_log

log ""
log "================================================================"
log "  $((PASS+FAIL)) scenarios - $PASS pass, $FAIL fail"
if (( FAIL > 0 )); then
    log "  failed: ${FAILED_IDS[*]}"
fi
log "================================================================"

if (( FAIL > 0 )); then
    exit 1
fi
exit 0
