#!/usr/bin/env bash
# Bundled-script unit tests for the git_review skill.
#
# Two surfaces: collect_review_evidence.sh, which gathers the git layer (and the
# forge layer through a stub gh) into a scratch directory, and
# extract_heading_range.sh, which cuts an inclusive heading range out of a
# drafted report. Every scenario stages its own sandbox under scratch/<id>/ and
# never touches the host repository's working tree.
# shellcheck disable=SC2329

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HERE="$SCRIPT_DIR"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/git_review"
COLLECT="$SKILL_DIR/scripts/collect_review_evidence.sh"
RANGE="$SKILL_DIR/scripts/extract_heading_range.sh"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/layer1.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

scenario() {
    local id=$1 desc=$2 body=$3
    log ""
    log "=== $id  $desc ==="
    if "$body"; then
        PASS=$((PASS + 1))
        log "  PASS"
    else
        FAIL=$((FAIL + 1))
        FAILED_IDS+=("$id")
        log "  FAIL"
    fi
}

# `check <label> <cmd...>` reports through the same tallies, which is what
# tests/lib/plugin_version.sh expects from a sourcing harness.
check() {
    local label=$1
    shift
    log ""
    log "=== $label ==="
    if "$@" >/dev/null 2>&1; then
        PASS=$((PASS + 1))
        log "  PASS"
    else
        FAIL=$((FAIL + 1))
        FAILED_IDS+=("$label")
        log "  FAIL"
    fi
}

assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" == *"$needle"* ]]; then
        return 0
    fi
    log "    [missing substring: $label]"
    log "      needle: $(printf '%q' "$needle")"
    return 1
}

assert_absent() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    fi
    log "    [unexpected substring: $label]"
    log "      needle: $(printf '%q' "$needle")"
    return 1
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

assert_file() {
    local label=$1 path=$2
    if [[ -s "$path" ]]; then
        return 0
    fi
    log "    [missing or empty file: $label -> $path]"
    return 1
}

identity() {
    git config user.email "harness@example.com"
    git config user.name "Harness"
}

# Stage one bare origin plus a clone with a base commit and a feature branch
# that adds, deletes, renames, and modifies paths, so one sandbox exercises the
# whole evidence set.
fresh_repo() {
    local id=$1
    local root="$SCRATCH/$id"

    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --bare --initial-branch=main "$root/origin.git" || return 1
    git clone --quiet "$root/origin.git" "$root/repo" 2>/dev/null || return 1
    (
        cd "$root/repo" || exit 1
        identity
        printf 'alpha one\nalpha two\n' > alpha.txt
        printf 'to be deleted\n' > gone.txt
        printf 'to be renamed\nsecond line\nthird line\n' > old_name.txt
        mkdir -p vendor
        printf 'vendored\n' > vendor/lib.txt
        git add -A
        git commit --quiet -m "seed the base tree"
        git push --quiet origin main
        git remote set-head origin main

        git checkout --quiet -b feature
        printf 'alpha one\nalpha two\nalpha three\n' > alpha.txt
        git rm --quiet gone.txt
        git mv old_name.txt new_name.txt
        printf 'key = "AKIAIOSFODNN7EXAMPLE"\ncache = "/home/alice/.cache"\n' > cfg.py
        printf 'generated\n' > api_generated.go
        git add -A
        git commit --quiet -m "feature: add, delete, rename, and modify"
        git push --quiet -u origin feature
    ) || return 1
    printf '%s' "$root/repo"
}

collect() {
    local repo=$1
    shift
    local out rc
    out=$(cd "$repo" && "$COLLECT" "$@" 2>&1) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# --- collect_review_evidence.sh ----------------------------------------------

s1_fetches_before_the_three_dot_diff() {
    local repo ret rc out ev fetch_line diff_line
    repo=$(fresh_repo s1) || return 1
    ev="$SCRATCH/s1/ev"

    ret=$(collect "$repo" --base main --head feature --out "$ev")
    rc=${ret%%|*}
    out=${ret#*|}

    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_file "steps.log" "$ev/steps.log" || ok=false
    assert_file "fetch.log" "$ev/fetch.log" || ok=false

    # The ordered step log is what proves the fetch preceded the diff rather
    # than merely also happening.
    fetch_line=$(grep -n 'fetch base and head refs' "$ev/steps.log" | head -1 | cut -d: -f1)
    diff_line=$(grep -n 'three-dot diff stat' "$ev/steps.log" | head -1 | cut -d: -f1)
    if [[ -z "$fetch_line" || -z "$diff_line" ]] || ((fetch_line >= diff_line)); then
        log "    [fetch did not precede the three-dot diff: fetch=$fetch_line diff=$diff_line]"
        ok=false
    fi
    assert_contains "fetch command recorded" "$(cat "$ev/fetch.log")" "git fetch --all --no-prune" || ok=false
    assert_contains "stdout points at the manifest" "$out" "manifest.txt" || ok=false
    $ok
}

# head_sync.txt answers a different question from counts.txt: how far the local
# branch sits from its own upstream, rather than from the base. It is the only
# input the fast-forward decision has, so a stale local head is reviewed
# silently when it is missing or wrong.
s20_head_sync_reports_the_upstream_relationship() {
    local repo ret ev sync side
    repo=$(fresh_repo s20) || return 1
    ev="$SCRATCH/s20/ev"

    # In sync first: feature was just pushed with an upstream set.
    ret=$(collect "$repo" --base main --head feature --out "$ev")
    sync=$(cat "$ev/head_sync.txt" 2>/dev/null)

    local ok=true
    assert_eq "exit" "${ret%%|*}" "0" || ok=false
    assert_contains "manifest lists head_sync" "$(cat "$ev/manifest.txt" 2>/dev/null)" "head_sync.txt" || ok=false
    assert_contains "branch named" "$sync" "branch: feature" || ok=false
    assert_contains "upstream named" "$sync" "upstream: origin/feature" || ok=false
    assert_contains "in sync when nothing moved" "$sync" "head_vs_upstream: in sync" || ok=false

    # A commit lands on the remote from a side clone, so the local branch falls
    # behind while its worktree stays clean.
    side="$SCRATCH/s20/side"
    git clone --quiet --branch feature "$SCRATCH/s20/origin.git" "$side" 2>/dev/null || return 1
    (
        cd "$side" || exit 1
        identity
        printf 'alpha one\nalpha two\nalpha three\nalpha four\n' > alpha.txt
        git add alpha.txt
        git commit --quiet -m "alpha.txt -> add the fourth line"
        git push --quiet origin feature
    ) || return 1

    ev="$SCRATCH/s20/ev2"
    ret=$(collect "$repo" --base main --head feature --out "$ev")
    sync=$(cat "$ev/head_sync.txt" 2>/dev/null)

    assert_eq "exit after the side push" "${ret%%|*}" "0" || ok=false
    assert_contains "behind by one" "$sync" "head_vs_upstream: behind 1" || ok=false
    # The two heads must be reported distinctly, so the report can name which
    # commit it reviewed and which one it should have.
    if [[ "$(printf '%s' "$sync" | sed -n 's/^local_head: //p')" == \
          "$(printf '%s' "$sync" | sed -n 's/^remote_head: //p')" ]]; then
        log "    [local_head and remote_head are equal after the side push]"
        ok=false
    fi

    # The remote-qualified form names the same branch, so its upstream resolves
    # rather than reading as a branch called origin/feature.
    ev="$SCRATCH/s20/ev3"
    collect "$repo" --base main --head origin/feature --out "$ev" >/dev/null
    sync=$(cat "$ev/head_sync.txt" 2>/dev/null)
    assert_contains "remote-qualified head resolves to the branch" "$sync" "branch: feature" || ok=false
    $ok
}

s2_manifest_lists_the_whole_evidence_set() {
    local repo ret ev manifest
    repo=$(fresh_repo s2) || return 1
    ev="$SCRATCH/s2/ev"
    ret=$(collect "$repo" --base main --head feature --out "$ev")
    manifest=$(cat "$ev/manifest.txt" 2>/dev/null)

    local ok=true
    assert_eq "exit" "${ret%%|*}" "0" || ok=false
    assert_contains "commits without merges" "$manifest" "commits_no_merges.txt" || ok=false
    assert_contains "commits along first parent" "$manifest" "commits_first_parent.txt" || ok=false
    assert_contains "removed hunks" "$manifest" "removed_hunks.txt" || ok=false
    assert_contains "base-side versions" "$manifest" "base_side/" || ok=false
    assert_contains "name-status" "$manifest" "name_status.txt" || ok=false
    assert_contains "merge base" "$manifest" "merge_base.txt" || ok=false
    assert_contains "counts" "$manifest" "counts.txt" || ok=false
    assert_contains "test merge" "$manifest" "merge_tree.txt" || ok=false
    assert_contains "secret scan" "$manifest" "secret_scan.txt" || ok=false
    assert_contains "size profile" "$manifest" "size_profile.txt" || ok=false
    assert_contains "gate list" "$manifest" "gates.txt" || ok=false
    $ok
}

s3_name_status_detects_the_rename() {
    local repo ev name_status
    repo=$(fresh_repo s3) || return 1
    ev="$SCRATCH/s3/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    name_status=$(cat "$ev/name_status.txt" 2>/dev/null)

    local ok=true
    assert_contains "rename status" "$name_status" "R" || ok=false
    assert_contains "rename old path" "$name_status" "old_name.txt" || ok=false
    assert_contains "rename new path" "$name_status" "new_name.txt" || ok=false
    assert_contains "deletion" "$name_status" "gone.txt" || ok=false
    assert_contains "modification" "$name_status" "alpha.txt" || ok=false
    $ok
}

s4_commit_lists_cover_both_walks() {
    local repo ev no_merges first_parent
    repo=$(fresh_repo s4) || return 1
    ev="$SCRATCH/s4/ev"

    # An in-branch merge from the base, so the two walks differ.
    (
        cd "$repo" || exit 1
        git checkout --quiet main
        # A path neither side of the merge touches, so the merge lands cleanly
        # and the two commit walks genuinely differ.
        printf 'base moved on\n' > base_only.txt
        git add base_only.txt
        git commit --quiet -m "base: add base_only.txt"
        git push --quiet origin main
        git checkout --quiet feature
        git merge --no-edit -m "merge main into feature" main >/dev/null 2>&1 || exit 1
        git push --quiet origin feature
    ) || return 1

    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    no_merges=$(cat "$ev/commits_no_merges.txt" 2>/dev/null)
    first_parent=$(cat "$ev/commits_first_parent.txt" 2>/dev/null)

    local ok=true
    assert_contains "branch work in the no-merges walk" "$no_merges" "feature: add, delete, rename, and modify" || ok=false
    assert_absent "merge commit excluded from the no-merges walk" "$no_merges" "merge main into feature" || ok=false
    assert_contains "merge commit visible along the first parent" "$first_parent" "merge main into feature" || ok=false
    $ok
}

s5_removed_hunks_and_base_side_versions() {
    local repo ev removed index deleted
    repo=$(fresh_repo s5) || return 1
    ev="$SCRATCH/s5/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    removed=$(cat "$ev/removed_hunks.txt" 2>/dev/null)
    index=$(cat "$ev/base_side/index.txt" 2>/dev/null)
    deleted=$(cat "$ev/base_side/gone.txt" 2>/dev/null)

    local ok=true
    assert_contains "removed line from the deleted file" "$removed" "-to be deleted" || ok=false
    assert_contains "deleted file in the base-side index" "$index" "gone.txt" || ok=false
    assert_contains "modified file in the base-side index" "$index" "alpha.txt" || ok=false
    assert_eq "base-side content of the deleted file" "$deleted" "to be deleted" || ok=false
    $ok
}

s6_clean_test_merge_reports_no_conflict() {
    local repo ev conflicts
    repo=$(fresh_repo s6) || return 1
    ev="$SCRATCH/s6/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    conflicts=$(cat "$ev/conflicts.txt" 2>/dev/null)

    local ok=true
    assert_contains "no conflicts" "$conflicts" "conflicts: none" || ok=false
    assert_contains "mergeable yes" "$conflicts" "structurally_mergeable: yes" || ok=false
    $ok
}

s7_conflicting_test_merge_names_the_file() {
    local repo ev conflicts
    repo=$(fresh_repo s7) || return 1
    ev="$SCRATCH/s7/ev"

    (
        cd "$repo" || exit 1
        git checkout --quiet main
        printf 'alpha one\nbase rewrote this\n' > alpha.txt
        git commit --quiet -am "base: rewrite alpha"
        git push --quiet origin main
        git checkout --quiet feature
    ) || return 1

    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    conflicts=$(cat "$ev/conflicts.txt" 2>/dev/null)

    local ok=true
    assert_contains "conflicts reported" "$conflicts" "conflicts: yes" || ok=false
    assert_contains "mergeable no" "$conflicts" "structurally_mergeable: no" || ok=false
    assert_contains "conflicting file named" "$conflicts" "alpha.txt" || ok=false
    $ok
}

s8_counts_and_merge_base() {
    local repo ev counts merge_base
    repo=$(fresh_repo s8) || return 1
    ev="$SCRATCH/s8/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    counts=$(cat "$ev/counts.txt" 2>/dev/null)
    merge_base=$(cat "$ev/merge_base.txt" 2>/dev/null)

    local ok=true
    assert_contains "ahead count" "$counts" "ahead: 1" || ok=false
    assert_contains "behind count" "$counts" "behind: 0" || ok=false
    assert_eq "merge base is the seed commit" "$merge_base" \
        "$(cd "$repo" && git rev-parse main)" || ok=false
    $ok
}

s9_secret_scan_finds_both_shapes() {
    local repo ev scan
    repo=$(fresh_repo s9) || return 1
    ev="$SCRATCH/s9/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    scan=$(cat "$ev/secret_scan.txt" 2>/dev/null)

    local ok=true
    assert_contains "credential pattern" "$scan" "AKIAIOSFODNN7EXAMPLE" || ok=false
    assert_contains "hardcoded home path" "$scan" "/home/alice/" || ok=false
    $ok
}

s10_size_profile_counts_generated_files() {
    local repo ev profile
    repo=$(fresh_repo s10) || return 1
    ev="$SCRATCH/s10/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    profile=$(cat "$ev/size_profile.txt" 2>/dev/null)

    local ok=true
    assert_contains "changed file count" "$profile" "changed_files: 5" || ok=false
    assert_contains "generated file count" "$profile" "generated_files: 1" || ok=false
    assert_contains "share is stated" "$profile" "binary_or_generated_share:" || ok=false
    assert_contains "generated path listed" "$profile" "api_generated.go" || ok=false
    $ok
}

s11_uncommitted_mode_reports_both_lanes() {
    local repo ev status worktree_diff local_commits
    repo=$(fresh_repo s11) || return 1
    ev="$SCRATCH/s11/ev"

    (
        cd "$repo" || exit 1
        git checkout --quiet main
        printf 'a local commit\n' > ahead.txt
        git add ahead.txt
        git commit --quiet -m "ahead.txt -> one commit ahead of the upstream"
        printf 'alpha one\nstaged edit\n' > alpha.txt
        git add alpha.txt
        printf 'unstaged edit\n' > vendor/lib.txt
        printf 'untracked\n' > brand_new.txt
    ) || return 1

    collect "$repo" --uncommitted --out "$ev" >/dev/null
    status=$(cat "$ev/worktree_status.txt" 2>/dev/null)
    worktree_diff=$(cat "$ev/worktree_diff.txt" 2>/dev/null)
    local_commits=$(cat "$ev/local_commits.txt" 2>/dev/null)

    local ok=true
    assert_contains "staged path" "$status" "alpha.txt" || ok=false
    assert_contains "unstaged path" "$status" "vendor/lib.txt" || ok=false
    assert_contains "untracked path" "$status" "brand_new.txt" || ok=false
    assert_contains "staged lane" "$worktree_diff" "### staged" || ok=false
    assert_contains "unstaged lane" "$worktree_diff" "### unstaged" || ok=false
    assert_contains "untracked content included" "$worktree_diff" "+untracked" || ok=false
    assert_contains "upstream named" "$local_commits" "upstream: origin/main" || ok=false
    assert_contains "ahead count" "$local_commits" "ahead: 1" || ok=false
    assert_contains "commit message carried" "$local_commits" "one commit ahead of the upstream" || ok=false
    $ok
}

s12_reads_only_and_leaves_the_tree_alone() {
    local repo ev before after stash worktrees
    repo=$(fresh_repo s12) || return 1
    ev="$SCRATCH/s12/ev"

    (cd "$repo" && printf 'dirty edit\n' >> alpha.txt) || return 1
    before=$(cd "$repo" && git status --porcelain --untracked-files=all)
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    after=$(cd "$repo" && git status --porcelain --untracked-files=all)
    stash=$(cd "$repo" && git stash list)
    worktrees=$(cd "$repo" && git worktree list | wc -l | tr -d ' ')

    local ok=true
    assert_eq "working tree unchanged" "$after" "$before" || ok=false
    assert_eq "no stash created" "$stash" "" || ok=false
    assert_eq "no extra worktree" "$worktrees" "1" || ok=false
    assert_contains "dirty state recorded" "$(cat "$ev/target.txt")" "worktree_state: dirty" || ok=false
    $ok
}

s13_forge_layer_absent_is_recorded() {
    local repo ev status
    repo=$(fresh_repo s13) || return 1
    ev="$SCRATCH/s13/ev"
    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    status=$(cat "$ev/forge/status.txt" 2>/dev/null)

    local ok=true
    # The origin here is a local path, so the git-only path applies whether or
    # not the operator has gh installed.
    assert_contains "forge layer unavailable" "$status" "forge layer unavailable" || ok=false
    $ok
}

s14_forge_layer_pages_threads_and_counts_them() {
    local repo ev counts threads pages
    repo=$(fresh_repo s14) || return 1
    ev="$SCRATCH/s14/ev"
    local root="$SCRATCH/s14"
    local payloads="$root/payloads"

    stage_gh_stub "$root" "$payloads" || return 1
    (
        cd "$repo" || exit 1
        git config "url.$root/origin.git.insteadOf" "https://github.com/acme/widget.git"
        git remote set-url origin "https://github.com/acme/widget.git"
    ) || return 1

    (
        cd "$repo" || exit 1
        PATH="$root/bin:$PATH" \
        GH_STUB_LOG="$root/gh_calls.log" \
        GH_STUB_PAYLOADS="$payloads" \
        "$COLLECT" --base main --head feature --out "$ev" --pr 7 --no-fetch
    ) >/dev/null 2>&1

    counts=$(cat "$ev/forge/counts.txt" 2>/dev/null)
    threads=$(cat "$ev/forge/review_threads.json" 2>/dev/null)
    pages=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pages"])' \
        "$ev/forge/review_threads.json" 2>/dev/null)

    local ok=true
    assert_contains "forge available" "$(cat "$ev/forge/status.txt")" "available" || ok=false
    assert_contains "issue comment count" "$counts" "issue_comments: 2" || ok=false
    assert_contains "review count" "$counts" "reviews: 1" || ok=false
    assert_contains "thread count with states" "$counts" "review_threads: 3 (resolved: 1, outdated: 1)" || ok=false
    assert_eq "both pages read" "$pages" "2" || ok=false
    assert_contains "resolved thread kept" "$threads" "T_resolved_naming" || ok=false
    assert_contains "outdated thread kept" "$threads" "T_outdated_import" || ok=false
    $ok
}

s15_usage_and_argument_handling() {
    local help_out help_rc missing_rc bad_rc not_a_repo_rc tmp
    help_out=$("$COLLECT" --help 2>&1) && help_rc=0 || help_rc=$?
    (cd "$SCRATCH" && "$COLLECT" --head feature >/dev/null 2>&1) && missing_rc=0 || missing_rc=$?
    (cd "$SCRATCH" && "$COLLECT" --nonsense >/dev/null 2>&1) && bad_rc=0 || bad_rc=$?
    tmp=$(mktemp -d)
    (cd "$tmp" && "$COLLECT" --base main --head feature >/dev/null 2>&1) && not_a_repo_rc=0 || not_a_repo_rc=$?
    rm -rf "$tmp"

    local ok=true
    assert_eq "help exit" "$help_rc" "0" || ok=false
    assert_contains "usage" "$help_out" "Usage:" || ok=false
    assert_contains "exit codes documented" "$help_out" "Exit codes:" || ok=false
    assert_eq "missing --base exits 1" "$missing_rc" "1" || ok=false
    assert_eq "unknown argument exits 1" "$bad_rc" "1" || ok=false
    assert_eq "outside a repository exits 2" "$not_a_repo_rc" "2" || ok=false
    $ok
}

# --- extract_heading_range.sh ------------------------------------------------

write_report() {
    local path=$1
    cat > "$path" <<'REPORT'
# Review of feature/export

Reviewed commit `abc1234`. Tree state: clean.

## What the changes do and implement

The branch adds an export command.

## What it retires

The legacy format table is gone.

## What is critical

The export path opens a network connection, which CHARTER.md forbids.

## Bugs it may introduce

The loop walks one past the end of rows.

## Decisions the implementer must make before fixing

Whether retries live here or in the transport.

## Can it be structurally merged as it is

Yes.
REPORT
}

s16_inclusive_heading_range() {
    local report out
    report="$SCRATCH/s16_report.md"
    write_report "$report"
    out=$("$RANGE" "$report" "What is critical" "Decisions the implementer must make before fixing")

    local ok=true
    assert_contains "starts at the from heading" "$out" "## What is critical" || ok=false
    assert_contains "carries the from section" "$out" "CHARTER.md forbids" || ok=false
    assert_contains "carries the middle section" "$out" "## Bugs it may introduce" || ok=false
    assert_contains "ends with the to heading" "$out" "## Decisions the implementer must make before fixing" || ok=false
    assert_contains "carries the to section" "$out" "Whether retries live here" || ok=false
    assert_absent "stops before the next heading" "$out" "## Can it be structurally merged as it is" || ok=false
    assert_absent "excludes earlier sections" "$out" "## What it retires" || ok=false
    $ok
}

s17_range_to_end_of_file() {
    local report out
    report="$SCRATCH/s17_report.md"
    write_report "$report"
    out=$("$RANGE" "$report" "Bugs it may introduce")

    local ok=true
    assert_contains "starts at the named heading" "$out" "## Bugs it may introduce" || ok=false
    assert_contains "runs to the last heading" "$out" "## Can it be structurally merged as it is" || ok=false
    assert_absent "excludes earlier sections" "$out" "## What is critical" || ok=false
    $ok
}

s18_range_errors_and_listing() {
    local report missing_rc backwards_rc unreadable_rc list_out
    report="$SCRATCH/s18_report.md"
    write_report "$report"

    "$RANGE" "$report" "No Such Heading" >/dev/null 2>&1 && missing_rc=0 || missing_rc=$?
    "$RANGE" "$report" "Can it be structurally merged as it is" "What it retires" \
        >/dev/null 2>&1 && backwards_rc=0 || backwards_rc=$?
    "$RANGE" "$SCRATCH/does_not_exist.md" "Anything" >/dev/null 2>&1 && unreadable_rc=0 || unreadable_rc=$?
    list_out=$("$RANGE" --list "$report")

    local ok=true
    assert_eq "absent heading exits 3" "$missing_rc" "3" || ok=false
    assert_eq "backwards range exits 3" "$backwards_rc" "3" || ok=false
    assert_eq "unreadable file exits 1" "$unreadable_rc" "1" || ok=false
    assert_contains "listing carries a heading" "$list_out" "What is critical" || ok=false
    $ok
}

s19_single_heading_range_is_that_section_alone() {
    local report out
    report="$SCRATCH/s19_report.md"
    write_report "$report"
    out=$("$RANGE" "$report" "What it retires" "What it retires")

    local ok=true
    assert_contains "the heading itself" "$out" "## What it retires" || ok=false
    assert_contains "its body" "$out" "legacy format table" || ok=false
    assert_absent "nothing after it" "$out" "## What is critical" || ok=false
    $ok
}

# --- stub gh ------------------------------------------------------------------

# A minimal stub gh for s14: serves two pages of review threads plus the other
# surfaces, and records every call.
stage_gh_stub() {
    local root=$1 payloads=$2
    mkdir -p "$root/bin" "$payloads"
    : > "$root/gh_calls.log"

    cat > "$root/bin/gh" <<'GH'
#!/usr/bin/env bash
set -uo pipefail
printf '%s\n' "$*" >> "${GH_STUB_LOG:?}"
serve() { [[ -f "$GH_STUB_PAYLOADS/$1" ]] && cat "$GH_STUB_PAYLOADS/$1" || printf '{}\n'; }
case "${1:-}" in
  auth) exit 0 ;;
  pr)
    if [[ "$*" == *"--json comments"* ]]; then serve comments.json
    elif [[ "$*" == *"--json reviews"* ]]; then serve reviews.json
    elif [[ "$*" == *"statusCheckRollup"* ]]; then serve checks.json
    else serve pr.json
    fi
    ;;
  api)
    if [[ "$*" == *"-F cursor="* ]]; then serve threads2.json
    elif [[ "$*" == *"query="* ]]; then serve threads1.json
    else printf '[]\n'
    fi
    ;;
  *) printf '{}\n' ;;
esac
GH
    chmod +x "$root/bin/gh"

    printf '{"number": 7, "headRefOid": "deadbeef"}\n' > "$payloads/pr.json"
    printf '{"comments": [{"body": "one"}, {"body": "two"}]}\n' > "$payloads/comments.json"
    printf '{"reviews": [{"body": "a review"}]}\n' > "$payloads/reviews.json"
    printf '{"statusCheckRollup": []}\n' > "$payloads/checks.json"

    cat > "$payloads/threads1.json" <<'JSON'
{"data": {"repository": {"pullRequest": {"reviewThreads": {
  "pageInfo": {"hasNextPage": true, "endCursor": "PAGE2"},
  "nodes": [{"id": "T_open", "isResolved": false, "isOutdated": false,
             "comments": {"nodes": [{"body": "open thread"}]}}]}}}}}
JSON
    cat > "$payloads/threads2.json" <<'JSON'
{"data": {"repository": {"pullRequest": {"reviewThreads": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [{"id": "T_resolved_naming", "isResolved": true, "isOutdated": false,
             "comments": {"nodes": [{"body": "resolved thread"}]}},
            {"id": "T_outdated_import", "isResolved": false, "isOutdated": true,
             "comments": {"nodes": [{"body": "outdated thread"}]}}]}}}}}
JSON
}

# --- run ----------------------------------------------------------------------

scenario s1  "fetch precedes the three-dot diff"                      s1_fetches_before_the_three_dot_diff
scenario s2  "manifest lists the whole evidence set"                  s2_manifest_lists_the_whole_evidence_set
scenario s3  "name-status detects the rename"                         s3_name_status_detects_the_rename
scenario s4  "commit lists cover the no-merges and first-parent walks" s4_commit_lists_cover_both_walks
scenario s5  "removed hunks and base-side versions of deleted files"  s5_removed_hunks_and_base_side_versions
scenario s6  "clean test merge reports no conflict"                   s6_clean_test_merge_reports_no_conflict
scenario s7  "conflicting test merge names the file"                  s7_conflicting_test_merge_names_the_file
scenario s8  "merge base and ahead/behind counts"                     s8_counts_and_merge_base
scenario s9  "secret scan finds a credential and a home path"         s9_secret_scan_finds_both_shapes
scenario s10 "size profile counts binary and generated files"         s10_size_profile_counts_generated_files
scenario s11 "uncommitted mode reports both lanes"                    s11_uncommitted_mode_reports_both_lanes
scenario s12 "collection reads only and leaves the tree alone"        s12_reads_only_and_leaves_the_tree_alone
scenario s13 "an absent forge layer is recorded, not assumed"         s13_forge_layer_absent_is_recorded
scenario s14 "forge layer pages threads and keeps resolved/outdated"  s14_forge_layer_pages_threads_and_counts_them
scenario s15 "flags: help, missing, unknown, and outside a repo"      s15_usage_and_argument_handling
scenario s16 "heading range is inclusive of both named headings"      s16_inclusive_heading_range
scenario s17 "a single heading runs to the end of the file"           s17_range_to_end_of_file
scenario s18 "range errors and the heading listing"                   s18_range_errors_and_listing
scenario s19 "the same heading twice is that section alone"           s19_single_heading_range_is_that_section_alone
scenario s20 "head_sync reports the upstream relationship"            s20_head_sync_reports_the_upstream_relationship

# The standing repo rules keep the plugin metadata in lockstep; assert the
# invariant rather than the literal version this change shipped at.
# shellcheck source=../../lib/plugin_version.sh
. "$HERE/../../lib/plugin_version.sh"
check_plugin_version_lockstep ai_dev

log ""
log "================================================================"
log "  $((PASS + FAIL)) scenarios - $PASS pass, $FAIL fail"
if ((FAIL > 0)); then
    log "  failed: ${FAILED_IDS[*]}"
fi
log "================================================================"

if ((FAIL > 0)); then
    exit 1
fi
exit 0
