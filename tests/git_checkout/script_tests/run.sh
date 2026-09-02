#!/usr/bin/env bash
# Bundled-script unit tests for the git_checkout skill.
# shellcheck disable=SC2329

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/git_checkout"
CHECKOUT="$SKILL_DIR/scripts/checkout_branch.sh"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/layer1.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

# Seed a bare repository with one commit on its default branch, so later clones
# never see an empty repository.
seed_bare() {
    local bare=$1
    local branch=$2
    local work

    git init --quiet --bare --initial-branch="$branch" "$bare"
    work="$(mktemp -d)"
    git clone --quiet "$bare" "$work/seed" 2>/dev/null
    (
        cd "$work/seed" || exit 1
        git config user.email "harness@example.com"
        git config user.name "Harness"
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
        git push --quiet -u origin "$branch"
    ) || {
        rm -rf "$work"
        return 1
    }
    rm -rf "$work"
}

# Push a branch into a bare repository from a throwaway clone, so the fixture's
# own clone has never fetched it.
push_branch() {
    local bare=$1
    local base=$2
    local branch=$3
    local file=$4
    local content=$5
    local work

    work="$(mktemp -d)"
    git clone --quiet "$bare" "$work/side" 2>/dev/null
    (
        cd "$work/side" || exit 1
        git config user.email "harness@example.com"
        git config user.name "Harness"
        git checkout --quiet "$base"
        git checkout --quiet -b "$branch"
        printf '%s\n' "$content" > "$file"
        git add "$file"
        git commit --quiet -m "$branch work"
        git push --quiet -u origin "$branch"
    ) || {
        rm -rf "$work"
        return 1
    }
    rm -rf "$work"
}

# Stage a fixture root holding one bare origin and one clone of it on main.
fresh_repo() {
    local id=$1
    local root="$SCRATCH/$id"

    rm -rf "$root"
    mkdir -p "$root"
    seed_bare "$root/origin.git" main || return 1
    git clone --quiet "$root/origin.git" "$root/repo" 2>/dev/null || return 1
    (
        cd "$root/repo" || exit 1
        git config user.email "harness@example.com"
        git config user.name "Harness"
        git remote set-head origin main
    ) || return 1
    printf '%s' "$root/repo"
}

add_remote() {
    local repo=$1 name=$2 bare=$3
    (cd "$repo" && git remote add "$name" "$bare")
}

run_checkout() {
    local repo=$1
    shift
    local out rc

    out=$(cd "$repo" && "$CHECKOUT" "$@" 2>&1) && rc=0 || rc=$?
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

assert_absent() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    fi
    log "    [unexpected substring: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

assert_current_branch() {
    local repo=$1 branch=$2 actual
    actual="$(cd "$repo" && git symbolic-ref --quiet --short HEAD 2>/dev/null)" || actual="DETACHED"
    assert_eq "current branch" "$actual" "$branch"
}

assert_symbolic_head() {
    local repo=$1
    if (cd "$repo" && git symbolic-ref --quiet HEAD >/dev/null); then
        return 0
    fi
    log "    [HEAD is detached; expected a symbolic ref]"
    return 1
}

assert_upstream() {
    local repo=$1 branch=$2 expected=$3 actual
    actual="$(cd "$repo" && git rev-parse --abbrev-ref --symbolic-full-name "$branch@{upstream}" 2>/dev/null)" ||
        actual="NONE"
    assert_eq "upstream of $branch" "$actual" "$expected"
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

assert_ref_exists() {
    local repo=$1 ref=$2
    if (cd "$repo" && git show-ref --verify --quiet "$ref"); then
        return 0
    fi
    log "    [missing ref: $ref]"
    return 1
}

assert_no_stash() {
    local repo=$1 entries
    entries="$(cd "$repo" && git stash list | wc -l | tr -d ' ')"
    assert_eq "stash entries" "$entries" "0"
}

assert_file_content() {
    local repo=$1 file=$2 expected=$3 actual
    actual="$(cd "$repo" && cat "$file" 2>/dev/null)"
    assert_eq "content of $file" "$actual" "$expected"
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

s1_remote_only_branch_creates_tracking_branch() {
    local repo ret rc out
    repo=$(fresh_repo s1) || return 1
    push_branch "$SCRATCH/s1/origin.git" main topic topic.txt "topic" || return 1

    ret=$(run_checkout "$repo" topic)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" topic || ok=false
    assert_upstream "$repo" topic "origin/topic" || ok=false
    assert_contains "created report" "$out" "Branch now checked out: topic (created by this run)." || ok=false
    assert_contains "upstream report" "$out" "Upstream: origin/topic." || ok=false
    assert_contains "previous report" "$out" "Previous branch: main." || ok=false
    $ok
}

s2_second_remote_branch_pushed_after_clone_resolves() {
    local repo ret rc out
    repo=$(fresh_repo s2) || return 1
    seed_bare "$SCRATCH/s2/fork.git" main || return 1
    add_remote "$repo" fork "$SCRATCH/s2/fork.git" || return 1
    # Pushed after the clone's last fetch, and only on the non-origin remote.
    push_branch "$SCRATCH/s2/fork.git" main late-topic late.txt "late" || return 1

    ret=$(run_checkout "$repo" late-topic)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" late-topic || ok=false
    assert_upstream "$repo" late-topic "fork/late-topic" || ok=false
    assert_contains "fetch covered every remote" "$out" "git fetch --all --no-prune" || ok=false
    assert_contains "single-remote resolution" "$out" "found at fork/late-topic only" || ok=false
    $ok
}

s3_successful_checkout_leaves_stale_remote_ref_in_place() {
    local repo ret rc out
    repo=$(fresh_repo s3) || return 1
    push_branch "$SCRATCH/s3/origin.git" main topic topic.txt "topic" || return 1
    # A remote-tracking ref for a branch the remote no longer has, in a
    # repository that has opted into pruning on fetch.
    (
        cd "$repo" || exit 1
        git update-ref refs/remotes/origin/stale-gone "$(git rev-parse origin/main)"
        git config fetch.prune true
    ) || return 1

    ret=$(run_checkout "$repo" topic)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" topic || ok=false
    assert_ref_exists "$repo" refs/remotes/origin/stale-gone || ok=false
    assert_contains "no-prune reported" "$out" "remote-tracking refs left unpruned" || ok=false
    $ok
}

s4_existing_local_branch_switches_without_creating() {
    local repo ret rc out
    repo=$(fresh_repo s4) || return 1
    (
        cd "$repo" || exit 1
        git checkout --quiet -b local-only
        printf 'local\n' > local.txt
        git add local.txt
        git commit --quiet -m "local work"
        git checkout --quiet main
    ) || return 1

    ret=$(run_checkout "$repo" local-only)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" local-only || ok=false
    assert_upstream "$repo" local-only "NONE" || ok=false
    assert_contains "already present report" "$out" \
        "Branch now checked out: local-only (already present; no tracking branch created)." || ok=false
    assert_absent "no creation claim" "$out" "created by this run" || ok=false
    $ok
}

s5_bare_name_on_two_remotes_holds_and_asks() {
    local repo ret rc out
    repo=$(fresh_repo s5) || return 1
    seed_bare "$SCRATCH/s5/fork.git" main || return 1
    add_remote "$repo" fork "$SCRATCH/s5/fork.git" || return 1
    push_branch "$SCRATCH/s5/origin.git" main shared o.txt "origin side" || return 1
    push_branch "$SCRATCH/s5/fork.git" main shared f.txt "fork side" || return 1

    ret=$(run_checkout "$repo" shared)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "3" || ok=false
    assert_current_branch "$repo" main || ok=false
    assert_branch_missing "$repo" shared || ok=false
    assert_contains "origin candidate" "$out" "- origin/shared" || ok=false
    assert_contains "fork candidate" "$out" "- fork/shared" || ok=false
    assert_contains "asks which remote" "$out" "which remote should the local branch shared track?" || ok=false
    assert_contains "nothing done" "$out" "Created nothing and switched nowhere." || ok=false
    $ok
}

s6_qualified_reentry_after_hold_tracks_chosen_remote() {
    local repo hold_ret hold_rc ret rc out
    repo=$(fresh_repo s6) || return 1
    seed_bare "$SCRATCH/s6/fork.git" main || return 1
    add_remote "$repo" fork "$SCRATCH/s6/fork.git" || return 1
    push_branch "$SCRATCH/s6/origin.git" main shared o.txt "origin side" || return 1
    push_branch "$SCRATCH/s6/fork.git" main shared f.txt "fork side" || return 1

    hold_ret=$(run_checkout "$repo" shared)
    hold_rc=${hold_ret%%|*}

    ret=$(run_checkout "$repo" fork/shared)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "first pass exit" "$hold_rc" "3" || ok=false
    assert_eq "re-entry exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" shared || ok=false
    assert_symbolic_head "$repo" || ok=false
    assert_upstream "$repo" shared "fork/shared" || ok=false
    assert_contains "created report" "$out" "Branch now checked out: shared (created by this run)." || ok=false
    $ok
}

s7_qualified_argument_selects_named_remote_without_asking() {
    local repo ret rc out
    repo=$(fresh_repo s7) || return 1
    seed_bare "$SCRATCH/s7/fork.git" main || return 1
    add_remote "$repo" fork "$SCRATCH/s7/fork.git" || return 1
    push_branch "$SCRATCH/s7/origin.git" main shared o.txt "origin side" || return 1
    push_branch "$SCRATCH/s7/fork.git" main shared f.txt "fork side" || return 1

    ret=$(run_checkout "$repo" origin/shared)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" shared || ok=false
    assert_symbolic_head "$repo" || ok=false
    assert_upstream "$repo" shared "origin/shared" || ok=false
    assert_absent "no ambiguity hold" "$out" "Ambiguous branch name" || ok=false
    assert_contains "selection reported" "$out" "selected by the remote-qualified argument" || ok=false
    $ok
}

s8_qualified_miss_reports_without_falling_through() {
    local repo ret rc out
    repo=$(fresh_repo s8) || return 1
    seed_bare "$SCRATCH/s8/fork.git" main || return 1
    add_remote "$repo" fork "$SCRATCH/s8/fork.git" || return 1
    # Only fork carries the branch; the argument names origin.
    push_branch "$SCRATCH/s8/fork.git" main solo s.txt "solo" || return 1

    ret=$(run_checkout "$repo" origin/solo)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "4" || ok=false
    assert_current_branch "$repo" main || ok=false
    assert_branch_missing "$repo" solo || ok=false
    assert_contains "miss on named remote" "$out" "Branch not found on origin" || ok=false
    assert_contains "nothing done" "$out" "Created nothing and switched nowhere." || ok=false
    assert_absent "no fallthrough switch" "$out" "Branch now checked out" || ok=false
    $ok
}

s9_restricted_refspec_reports_that_cause() {
    local repo ret rc out root
    root="$SCRATCH/s9"
    rm -rf "$root"
    mkdir -p "$root"
    seed_bare "$root/origin.git" main || return 1
    push_branch "$root/origin.git" main hidden h.txt "hidden" || return 1
    git clone --quiet --single-branch --branch main "$root/origin.git" "$root/repo" 2>/dev/null || return 1
    repo="$root/repo"
    (
        cd "$repo" || exit 1
        git config user.email "harness@example.com"
        git config user.name "Harness"
    ) || return 1

    ret=$(run_checkout "$repo" hidden)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "4" || ok=false
    assert_current_branch "$repo" main || ok=false
    assert_branch_missing "$repo" hidden || ok=false
    assert_contains "refspec cause" "$out" \
        "narrow fetch refspec or single-branch clone never maps it into refs/remotes/" || ok=false
    assert_contains "refspec shown" "$out" "+refs/heads/main:refs/remotes/origin/main" || ok=false
    assert_contains "remedy shown" "$out" "git remote set-branches --add origin hidden" || ok=false
    assert_absent "not a bare pathspec relay" "$out" "did not match any file" || ok=false
    $ok
}

s10_nonexistent_branch_reports_nonexistence() {
    local repo ret rc out
    repo=$(fresh_repo s10) || return 1

    ret=$(run_checkout "$repo" never-existed)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "4" || ok=false
    assert_current_branch "$repo" main || ok=false
    assert_branch_missing "$repo" never-existed || ok=false
    assert_contains "nonexistent cause" "$out" \
        "no remote advertises refs/heads/never-existed, so the branch does not exist" || ok=false
    assert_contains "nothing done" "$out" "Created nothing and switched nowhere." || ok=false
    $ok
}

s11_conflicting_dirty_worktree_blocks_without_stashing() {
    local repo ret rc out
    repo=$(fresh_repo s11) || return 1
    # topic rewrites a tracked file the worktree also modified.
    push_branch "$SCRATCH/s11/origin.git" main topic seed.txt "topic version" || return 1
    (
        cd "$repo" || exit 1
        printf 'local uncommitted\n' > seed.txt
    ) || return 1

    ret=$(run_checkout "$repo" topic)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "5" || ok=false
    assert_current_branch "$repo" main || ok=false
    assert_branch_missing "$repo" topic || ok=false
    assert_file_content "$repo" seed.txt "local uncommitted" || ok=false
    assert_no_stash "$repo" || ok=false
    assert_contains "block reported" "$out" "Switch blocked" || ok=false
    assert_contains "blocking paths" "$out" "Blocking paths:" || ok=false
    assert_contains "blocking path named" "$out" "seed.txt" || ok=false
    assert_contains "worktree kept" "$out" "ran no stash, reset, or checkout-discard" || ok=false
    assert_contains "branch still checked out" "$out" "Branch still checked out: main." || ok=false
    $ok
}

s12_non_conflicting_dirty_worktree_carries_changes_across() {
    local repo ret rc out status
    repo=$(fresh_repo s12) || return 1
    push_branch "$SCRATCH/s12/origin.git" main topic topic.txt "topic" || return 1
    (
        cd "$repo" || exit 1
        printf 'work in progress\n' > scratch.txt
    ) || return 1

    ret=$(run_checkout "$repo" topic)
    rc=${ret%%|*}
    out=${ret#*|}
    status="$(cd "$repo" && git status --porcelain)"

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" topic || ok=false
    assert_file_content "$repo" scratch.txt "work in progress" || ok=false
    assert_contains "change still uncommitted" "$status" "scratch.txt" || ok=false
    assert_no_stash "$repo" || ok=false
    assert_contains "switch completed" "$out" "Branch now checked out: topic (created by this run)." || ok=false
    $ok
}

s13_slashed_branch_name_is_not_read_as_a_remote() {
    local repo ret rc out
    repo=$(fresh_repo s13) || return 1
    push_branch "$SCRATCH/s13/origin.git" main feature/login login.txt "login" || return 1

    ret=$(run_checkout "$repo" feature/login)
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_current_branch "$repo" feature/login || ok=false
    assert_symbolic_head "$repo" || ok=false
    assert_upstream "$repo" feature/login "origin/feature/login" || ok=false
    assert_branch_exists "$repo" feature/login || ok=false
    assert_contains "resolved whole name" "$out" "found at origin/feature/login only" || ok=false
    $ok
}

s14_usage_and_argument_handling() {
    local repo ret rc out empty_rc extra_rc
    repo=$(fresh_repo s14) || return 1

    ret=$(run_checkout "$repo" --help)
    rc=${ret%%|*}
    out=${ret#*|}
    (cd "$repo" && "$CHECKOUT" >/dev/null 2>&1) && empty_rc=0 || empty_rc=$?
    (cd "$repo" && "$CHECKOUT" main extra >/dev/null 2>&1) && extra_rc=0 || extra_rc=$?

    local ok=true
    assert_eq "help exit" "$rc" "0" || ok=false
    assert_contains "usage" "$out" "Usage:" || ok=false
    assert_contains "exit codes documented" "$out" "Exit codes:" || ok=false
    assert_eq "missing argument exit" "$empty_rc" "1" || ok=false
    assert_eq "extra argument exit" "$extra_rc" "1" || ok=false
    $ok
}

scenario s1  "remote-only branch: create tracking branch with explicit upstream" s1_remote_only_branch_creates_tracking_branch
scenario s2  "second remote, pushed after clone: fetch covers every remote"      s2_second_remote_branch_pushed_after_clone_resolves
scenario s3  "successful checkout leaves a stale remote-tracking ref in place"   s3_successful_checkout_leaves_stale_remote_ref_in_place
scenario s4  "already local: switch and report no tracking branch created"       s4_existing_local_branch_switches_without_creating
scenario s5  "two remotes, bare name: hold with candidates and create nothing"   s5_bare_name_on_two_remotes_holds_and_asks
scenario s6  "re-entry with the qualified form tracks the chosen remote"         s6_qualified_reentry_after_hold_tracks_chosen_remote
scenario s7  "qualified argument selects its remote without asking"              s7_qualified_argument_selects_named_remote_without_asking
scenario s8  "qualified miss reports without falling through to another remote"   s8_qualified_miss_reports_without_falling_through
scenario s9  "restricted fetch refspec: report that cause and the remedy"        s9_restricted_refspec_reports_that_cause
scenario s10 "branch on no remote: report nonexistence and create nothing"       s10_nonexistent_branch_reports_nonexistence
scenario s11 "conflicting dirty worktree: block, name paths, run no stash"       s11_conflicting_dirty_worktree_blocks_without_stashing
scenario s12 "non-conflicting dirty worktree: switch with changes intact"        s12_non_conflicting_dirty_worktree_carries_changes_across
scenario s13 "slashed branch name is not read as a remote-qualified argument"    s13_slashed_branch_name_is_not_read_as_a_remote
scenario s14 "flags: help, missing argument, and extra argument handling"        s14_usage_and_argument_handling

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
