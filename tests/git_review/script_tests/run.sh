#!/usr/bin/env bash
# Bundled-script unit tests for the git_review skill.
#
# Covers collect_review_evidence.sh, which gathers the git layer (and the
# forge layer through a stub gh) into a scratch directory, and
# extract_heading_range.sh, which cuts an inclusive heading range out of a
# drafted report, plus the grader's report-form discrimination, the eval-32
# delta-tag fail branches, and the eval-41 push-order proofs (hook log,
# TMPDIR-scoped report.md, and grader fail branches). Repository scenarios
# stage their own sandbox under scratch/<id>/; form checks read fixtures.
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

# Read one `key: value` line from a size_profile.txt (or similar) file.
profile_value() {
    local file=$1 key=$2
    awk -F': ' -v k="$key" '$1 == k { print $2; exit }' "$file"
}

# Print each binary_or_generated_paths entry of a size_profile.txt, one per
# line without its indent, in byte order.
profile_paths() {
    awk 'listing && /^  / { print substr($0, 3); next }
         { listing = ($0 == "binary_or_generated_paths:") }' "$1" | LC_ALL=C sort
}

# A listed path is a path. An entry that is still a Binary files line, or its
# tail, means the listing parsed that line instead of the section's opener.
assert_paths_are_paths() {
    local label=$1 paths=$2 entry ok=true
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        if [[ "$entry" == "Binary files"* || "$entry" == *differ ]]; then
            log "    [listed entry is a Binary files line: $label]"
            log "      entry: $(printf '%q' "$entry")"
            ok=false
        fi
    done <<< "$paths"
    $ok
}

# Sum added and removed columns from `git diff --numstat` on stdin, skipping
# binary rows where either column is `-`. Prints "added removed".
sum_numstat_text() {
    awk '$1 != "-" && $2 != "-" { a += $1; r += $2 }
         END { printf "%d %d\n", a + 0, r + 0 }'
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
    local repo ev status worktree_diff local_commits profile
    local staged_sum unstaged_sum expect_added expect_removed actual_added actual_removed
    local sa sr ua ur untracked_lines
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
    profile=$(cat "$ev/size_profile.txt" 2>/dev/null)

    staged_sum=$(cd "$repo" && git diff --cached --numstat | sum_numstat_text)
    unstaged_sum=$(cd "$repo" && git diff --numstat | sum_numstat_text)
    sa=${staged_sum%% *}; sr=${staged_sum##* }
    ua=${unstaged_sum%% *}; ur=${unstaged_sum##* }
    untracked_lines=0
    while IFS= read -r f; do
        [[ -z "$f" || ! -f "$repo/$f" ]] && continue
        untracked_lines=$((untracked_lines + $(wc -l < "$repo/$f" | tr -d ' ')))
    done < <(cd "$repo" && git ls-files --others --exclude-standard)
    expect_added=$((sa + ua + untracked_lines))
    expect_removed=$((sr + ur))
    actual_added=$(profile_value "$ev/size_profile.txt" added_lines)
    actual_removed=$(profile_value "$ev/size_profile.txt" removed_lines)

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
    assert_eq "uncommitted added_lines match lane numstats plus untracked" \
        "$actual_added" "$expect_added" || ok=false
    assert_eq "uncommitted removed_lines match lane numstats" \
        "$actual_removed" "$expect_removed" || ok=false
    assert_contains "size profile present" "$profile" "added_lines:" || ok=false
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

    # The resolved thread's comments run onto a second page, which only a
    # request through the thread's own node id reaches.
    local comment_pages
    comment_pages=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["comment_pages"])' \
        "$ev/forge/review_threads.json" 2>/dev/null)
    assert_contains "comment page requested by thread id" \
        "$(cat "$root/gh_calls.log" 2>/dev/null)" "id=T_resolved_naming" || ok=false
    assert_contains "second comment page folded into its thread" "$threads" "second-page reply" || ok=false
    assert_eq "one comment page followed" "$comment_pages" "1" || ok=false
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

# The unreadable_path fixture hides one changed blob from git. The collector
# must keep the readable path in the evidence set and record the locked path as
# unread rather than emptying the whole-range diff, and the secret scan must
# read the readable per-path diffs rather than the whole-range diff that failed.
# A non-ASCII path, which name_status.txt shows git-quoted, must still be read
# and scanned by the collector and by both manual-fallback per-path loops.
s22_unreadable_path_records_unread_remainder() {
    local target repo ret ev ok=true
    local path status expect_added expect_removed actual_added actual_removed path_sum pa pr
    local fallback collector_labeled fallback_labeled retry_block retry_out unread_file fb_shell
    target="$SCRATCH/s22"
    rm -rf "$target"
    mkdir -p "$target"
    repo=$("$HERE/../evals/fixtures/unreadable_path/setup.sh" "$target") || return 1
    (
        cd "$repo" || exit 1
        printf 'readable = 3\nAWS = "AKIAIOSFODNN7EXAMPLE"\n' > src/readable.py
        printf 'nonascii_marker = 1\nKEY = "AKIAIOSFODNN7EXAMPLE"\n' > ä.txt
        git add src/readable.py ä.txt
        git commit --quiet -m "readable keys"
    ) || return 1
    ev="$target/ev"
    ret=$(collect "$repo" --base main --head widen --out "$ev" --no-fetch)
    assert_eq "exit" "${ret%%|*}" "0" || ok=false
    assert_contains "unread_paths lists locked.py" "$(cat "$ev/unread_paths.txt" 2>/dev/null)" \
        "src/locked.py" || ok=false
    assert_contains "manifest lists unread_paths" "$(cat "$ev/manifest.txt" 2>/dev/null)" \
        "unread_paths.txt" || ok=false
    assert_contains "full_diff keeps readable.py" "$(cat "$ev/full_diff.txt" 2>/dev/null)" \
        "src/readable.py" || ok=false
    assert_contains "diff_stat keeps readable.py" "$(cat "$ev/diff_stat.txt" 2>/dev/null)" \
        "src/readable.py" || ok=false
    assert_contains "removed_hunks keeps readable.py" "$(cat "$ev/removed_hunks.txt" 2>/dev/null)" \
        "src/readable.py" || ok=false
    assert_absent "full_diff hides secret_flag" "$(cat "$ev/full_diff.txt" 2>/dev/null)" \
        "secret_flag" || ok=false
    assert_contains "secret scan reads the readable per-path diff" \
        "$(cat "$ev/secret_scan.txt" 2>/dev/null)" \
        'src/readable.py:2:AWS = "AKIAIOSFODNN7EXAMPLE"' || ok=false
    assert_contains "name_status quotes the non-ascii path" "$(cat "$ev/name_status.txt" 2>/dev/null)" \
        '"\303\244.txt"' || ok=false
    assert_contains "full_diff keeps the non-ascii path" "$(cat "$ev/full_diff.txt" 2>/dev/null)" \
        "nonascii_marker" || ok=false
    assert_eq "unread_paths lists only locked.py" "$(cat "$ev/unread_paths.txt" 2>/dev/null)" \
        "src/locked.py" || ok=false
    assert_contains "secret scan reads the non-ascii per-path diff" \
        "$(cat "$ev/secret_scan.txt" 2>/dev/null)" \
        'ä.txt:2:KEY = "AKIAIOSFODNN7EXAMPLE"' || ok=false

    # The manual fallback's per-path scan finds the same hits.
    fallback="$SKILL_DIR/references/manual_fallback.md"
    collector_labeled=$(
        labeled_scan_hits "$ev/secret_scan.txt" "credential_pattern_hits:" credential
        labeled_scan_hits "$ev/secret_scan.txt" "hardcoded_home_path_hits:" home
    )
    collector_labeled=$(printf '%s\n' "$collector_labeled" | sed '/^$/d' | sort)
    while IFS= read -r fb_shell; do
        fallback_labeled=$(
            cd "$repo" && BASE=main HEAD_REF=widen \
                run_fallback_block "$fb_shell" "$(fallback_scan_block "$fallback")" 2>/dev/null
        )
        fallback_labeled=$(printf '%s\n' "$fallback_labeled" | sed '/^$/d' | sort)
        assert_eq "per-path fallback extraction matches the collector hits under $fb_shell" \
            "$fallback_labeled" "$collector_labeled" || ok=false
    done < <(fallback_shells)

    # The manual fallback's per-path evidence retry reads the non-ascii path,
    # records only the locked path as unread, and writes that record outside
    # the working tree, also when it runs from a subdirectory.
    retry_block=$(awk '
        /^# per-path retry when the whole-range diff fails$/ { on = 1 }
        on && /^```$/ { exit }
        on { print }
    ' "$fallback")
    while IFS= read -r fb_shell; do
        retry_out=$(cd "$repo/src" && BASE=main HEAD_REF=widen \
            run_fallback_block "$fb_shell" "$retry_block" 2>/dev/null)
        assert_contains "fallback retry reads the non-ascii path under $fb_shell" \
            "$retry_out" "nonascii_marker" || ok=false
        unread_file=$(printf '%s\n' "$retry_out" | sed -n 's/^unread_paths\.txt: //p' | tail -1)
        assert_eq "fallback retry lists only locked.py under $fb_shell" \
            "$(cat "$unread_file" 2>/dev/null)" "src/locked.py" || ok=false
        if [[ -e "$repo/unread_paths.txt" || -e "$repo/src/unread_paths.txt" ]]; then
            log "    [fallback retry under $fb_shell wrote unread_paths.txt into the working tree]"
            ok=false
        fi
        [[ -n "$unread_file" ]] && rm -rf "$(dirname "$unread_file")"
    done < <(fallback_shells)

    # A retry loop that reads into status, which zsh keeps read-only, must
    # fail the zsh run, so the check above can catch that name.
    if command -v zsh >/dev/null 2>&1; then
        retry_out=$(cd "$repo/src" && BASE=main HEAD_REF=widen \
            run_fallback_block zsh "${retry_block//name_status/status}" 2>/dev/null)
        if [[ "$retry_out" == *nonascii_marker* ]]; then
            log "    [zsh retry check passed with a loop that reads into status]"
            ok=false
        fi
    fi

    # Size profile counts only the readable paths the per-path fallback kept.
    expect_added=0
    expect_removed=0
    while IFS= read -r -d '' status; do
        IFS= read -r -d '' path || break
        case "$status" in
            R*|C*) IFS= read -r -d '' path || break ;;
        esac
        grep -qxF "$path" "$ev/unread_paths.txt" 2>/dev/null && continue
        path_sum=$(git -C "$repo" diff --numstat -M "main...widen" -- "$path" 2>/dev/null |
            sum_numstat_text)
        pa=${path_sum%% *}; pr=${path_sum##* }
        expect_added=$((expect_added + pa))
        expect_removed=$((expect_removed + pr))
    done < <(git -C "$repo" diff --name-status -z -M "main...widen" 2>/dev/null)
    actual_added=$(profile_value "$ev/size_profile.txt" added_lines)
    actual_removed=$(profile_value "$ev/size_profile.txt" removed_lines)
    assert_eq "per-path fallback added_lines match readable numstat" \
        "$actual_added" "$expect_added" || ok=false
    assert_eq "per-path fallback removed_lines match readable numstat" \
        "$actual_removed" "$expect_removed" || ok=false

    # Acceptance git-command hide checks on the staged sandbox.
    git -C "$repo" show "HEAD:src/locked.py" >/dev/null 2>&1 && {
        log "    [git show HEAD:src/locked.py unexpectedly succeeded]"
        ok=false
    }
    git -C "$repo" diff "main...HEAD" -- src/locked.py >/dev/null 2>&1 && {
        log "    [git diff of src/locked.py unexpectedly succeeded]"
        ok=false
    }
    git -C "$repo" show "HEAD:src/readable.py" >/dev/null 2>&1 || {
        log "    [git show HEAD:src/readable.py failed]"
        ok=false
    }
    git -C "$repo" fetch --all >/dev/null 2>&1 || {
        log "    [git fetch --all failed]"
        ok=false
    }
    test ! -e "$repo/src/locked.py" || {
        log "    [src/locked.py is present in the worktree]"
        ok=false
    }
    $ok
}

# Range-mode size profile: content-line counts equal git diff --numstat, and the
# fixture keeps hunk lines that begin with --- / +++ so a header-inclusive or
# plain grep -v filter would miscount. The feature branch also modifies one
# binary, adds one, and deletes one, so the range diff carries all three
# Binary files forms and the listing must name each binary by its path.
s24_size_profile_line_counts_match_numstat() {
    local root repo ev ok=true
    local expect_sum expect_added expect_removed actual_added actual_removed full_diff
    local name entry expected_paths listed_paths name_only
    root="$SCRATCH/s24"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --bare --initial-branch=main "$root/origin.git" || return 1
    git clone --quiet "$root/origin.git" "$root/repo" 2>/dev/null || return 1
    (
        cd "$root/repo" || exit 1
        identity
        printf 'keep\n-- note\nalso keep\n' > notes.sql
        printf 'plain\n' > keep.txt
        printf 'rename me\n' > old_name.txt
        printf 'delete me\n' > gone.txt
        # NUL so git treats this as binary (numstat prints -, no ---/+++ pair).
        printf 'bin\000v1' > data.bin
        printf 'old\000payload the feature branch deletes' > removed.bin
        git add -A
        git commit --quiet -m "seed the size-profile fixture"
        git push --quiet origin main
        git remote set-head origin main

        git checkout --quiet -b feature
        # Remove the SQL comment so the hunk carries a content line "--- note".
        printf 'keep\nalso keep\n' > notes.sql
        # Add a line that begins with ++ so the hunk carries "+++ x".
        printf 'plain\n++ x\n' > keep.txt
        printf 'brand new\n' > added.txt
        git rm --quiet gone.txt
        git mv old_name.txt new_name.txt
        printf 'bin\000v2-longer' > data.bin
        # Content unlike removed.bin, so rename detection keeps the two apart.
        printf 'new\000%s' 'ADDED 0123456789' > added.bin
        git rm --quiet removed.bin
        git add -A
        git commit --quiet -m "feature: modify, add, delete, rename, binaries, and ---/+++ content"
        git push --quiet -u origin feature
    ) || return 1
    repo="$root/repo"
    ev="$root/ev"

    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    expect_sum=$(cd "$repo" && git diff --numstat -M "main...feature" | sum_numstat_text)
    expect_added=${expect_sum%% *}
    expect_removed=${expect_sum##* }
    actual_added=$(profile_value "$ev/size_profile.txt" added_lines)
    actual_removed=$(profile_value "$ev/size_profile.txt" removed_lines)
    full_diff=$(cat "$ev/full_diff.txt" 2>/dev/null)

    assert_eq "range added_lines match numstat" "$actual_added" "$expect_added" || ok=false
    assert_eq "range removed_lines match numstat" "$actual_removed" "$expect_removed" || ok=false
    # Hunk content (not the file headers): a removed "-- note" and an added "++ x".
    if ! printf '%s\n' "$full_diff" | grep -E '^--- note$' >/dev/null; then
        log "    [missing hunk content line --- note]"
        ok=false
    fi
    if ! printf '%s\n' "$full_diff" | grep -E '^\+\+\+ x$' >/dev/null; then
        log "    [missing hunk content line +++ x]"
        ok=false
    fi
    # Confirm the fixture exercised every Approach-named edit class.
    assert_contains "name-status records the rename" \
        "$(cat "$ev/name_status.txt" 2>/dev/null)" "old_name.txt" || ok=false
    assert_contains "name-status records the deletion" \
        "$(cat "$ev/name_status.txt" 2>/dev/null)" "gone.txt" || ok=false
    assert_contains "name-status records the addition" \
        "$(cat "$ev/name_status.txt" 2>/dev/null)" "added.txt" || ok=false
    # The feature branch adds one binary and deletes another; numstat prints -
    # for a binary row.
    if ! (cd "$repo" && git diff --numstat -M --diff-filter=A "main...feature") |
            grep -Fqx -e "$(printf -- '-\t-\tadded.bin')"; then
        log "    [feature branch does not add the binary added.bin]"
        ok=false
    fi
    if ! (cd "$repo" && git diff --numstat -M --diff-filter=D "main...feature") |
            grep -Fqx -e "$(printf -- '-\t-\tremoved.bin')"; then
        log "    [feature branch does not delete the binary removed.bin]"
        ok=false
    fi
    # binary_files: 3 fails when any of the three is still text; a name-only
    # check cannot.
    assert_eq "size profile counts the modified, added, and deleted binary" \
        "$(profile_value "$ev/size_profile.txt" binary_files)" "3" || ok=false
    # Each binary is listed as git diff --name-only prints it, whichever of the
    # three Binary files forms its section carries.
    name_only=$(cd "$repo" && git diff --name-only "main...feature")
    expected_paths=""
    for name in data.bin added.bin removed.bin; do
        entry=$(printf '%s\n' "$name_only" | grep -Fx "$name")
        if [[ -z "$entry" ]]; then
            log "    [git diff --name-only does not print $name]"
            ok=false
            continue
        fi
        expected_paths+="$entry"$'\n'
    done
    expected_paths=$(printf '%s' "$expected_paths" | LC_ALL=C sort)
    listed_paths=$(profile_paths "$ev/size_profile.txt")
    assert_eq "listing names the modified, added, and deleted binary" \
        "$listed_paths" "$expected_paths" || ok=false
    assert_paths_are_paths "range listing" "$listed_paths" || ok=false
    $ok
}

# Uncommitted size profile over an unresolved merge. One text file merges
# cleanly into the staged lane, and three paths stay unmerged (UU), so the
# unstaged lane opens each with diff --cc: a text file, a text file with a
# non-ASCII name under a top-level vendor/ directory, whose opener git quotes,
# and a binary whose name holds a space. A staged added binary and the staged
# deletion of a binary with a non-ASCII name carry the two Binary files forms
# against /dev/null. Each conflicted text file differs from HEAD by its one
# conflict hunk alone, so its diff --cc section drops no hunk and its line
# count equals git diff --numstat HEAD. No path is both staged and unstaged
# and no file is untracked, so each changed path forms exactly one section.
s30_size_profile_reads_conflicted_sections() {
    local root repo ev ok=true profile_file worktree_diff
    local unmerged staged_added staged_deleted vendor_entry binary_entry entry inner minus plus header
    local porcelain_count expect_sum total binary generated
    local expected_paths listed_paths leftover
    root="$SCRATCH/s30"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --initial-branch=main "$root/repo" || return 1
    repo="$root/repo"
    (
        cd "$repo" || exit 1
        identity
        git config core.quotepath true
        mkdir -p vendor
        printf 'one\ntwo\nthree\nfour\nfive\n' > conflict.txt
        printf 'v1\nv2\nv3\n' > vendor/ä.txt
        printf 'bin\000base' > 'conflict bin.bin'
        printf 'bin\000the staged deletion' > ö.bin
        printf 'clean\nfile\n' > clean.txt
        git add -A
        git commit --quiet -m "seed the merge fixture"

        git checkout --quiet -b left
        printf 'one\ntwo\nLEFT\nfour\nfive\n' > conflict.txt
        printf 'v1\nLEFT\nv3\n' > vendor/ä.txt
        printf 'bin\000left' > 'conflict bin.bin'
        git commit --quiet -am "left side"

        git checkout --quiet main
        git checkout --quiet -b right
        printf 'one\ntwo\nRIGHT\nfour\nfive\n' > conflict.txt
        printf 'v1\nRIGHT\nv3\n' > vendor/ä.txt
        printf 'bin\000right' > 'conflict bin.bin'
        printf 'clean\nfile\nmerged cleanly\n' > clean.txt
        git commit --quiet -am "right side"

        git checkout --quiet left
        git merge right >/dev/null 2>&1 && exit 1
        printf 'added\000binary' > added.bin
        git add added.bin
        git rm --quiet ö.bin
    ) || return 1
    ev="$root/ev"
    collect "$repo" --uncommitted --no-fetch --out "$ev" >/dev/null
    profile_file="$ev/size_profile.txt"
    worktree_diff=$(cat "$ev/worktree_diff.txt" 2>/dev/null)

    unmerged=$(cd "$repo" && git diff --name-only --diff-filter=U)
    staged_added=$(cd "$repo" && git diff --cached --name-only --diff-filter=A)
    staged_deleted=$(cd "$repo" && git diff --cached --name-only --diff-filter=D)
    vendor_entry=$(printf '%s\n' "$unmerged" | grep -E '^"?vendor/')
    binary_entry=$(printf '%s\n' "$unmerged" | grep -E '\.bin"?$')

    # Guard the fixture shape the assertions below rely on.
    assert_eq "three paths stay unmerged" "$(printf '%s\n' "$unmerged" | grep -c .)" "3" || ok=false
    assert_eq "no file is untracked" \
        "$(cd "$repo" && git ls-files --others --exclude-standard)" "" || ok=false
    assert_eq "one staged added binary" "$staged_added" "added.bin" || ok=false
    [[ "$vendor_entry" == '"'*'\303\244'*'"' ]] || {
        log "    [the conflicted vendor/ path is not git-quoted: $vendor_entry]"
        ok=false
    }
    [[ "$binary_entry" == *' '* && "$binary_entry" != '"'* ]] || {
        log "    [the conflicted binary name holds no space or is quoted: $binary_entry]"
        ok=false
    }
    [[ "$staged_deleted" == '"'*'\303\266'*'"' ]] || {
        log "    [the staged deletion is not git-quoted: $staged_deleted]"
        ok=false
    }

    # Every conflicted path keeps its combined diff in the evidence: a diff --cc
    # opener, each text file's --- and +++ headers, and the conflicted binary's
    # bare Binary files line.
    while IFS= read -r entry; do
        [[ -z "$entry" ]] && continue
        printf '%s\n' "$worktree_diff" | grep -Fqx "diff --cc $entry" || {
            log "    [worktree_diff.txt has no diff --cc line for $entry]"
            ok=false
        }
        [[ "$entry" == "$binary_entry" ]] && continue
        # git quotes a header path where it quotes the name, a/ or b/ inside.
        if [[ "$entry" == '"'* ]]; then
            inner=${entry#\"}
            minus="--- \"a/$inner"
            plus="+++ \"b/$inner"
        else
            minus="--- a/$entry"
            plus="+++ b/$entry"
        fi
        for header in "$minus" "$plus"; do
            printf '%s\n' "$worktree_diff" | grep -Fqx -- "$header" || {
                log "    [worktree_diff.txt lacks the header line $header]"
                ok=false
            }
        done
    done <<< "$unmerged"
    printf '%s\n' "$worktree_diff" | grep -Fqx 'Binary files differ' || {
        log "    [worktree_diff.txt has no bare Binary files differ line]"
        ok=false
    }

    # Each changed path is one section, conflicted ones included.
    porcelain_count=$(cd "$repo" && git status --porcelain | grep -c .)
    total=$(profile_value "$profile_file" changed_files)
    assert_eq "changed_files counts every path git status lists" "$total" "$porcelain_count" || ok=false

    expect_sum=$(cd "$repo" && git diff --numstat HEAD | sum_numstat_text)
    assert_eq "added_lines match numstat against HEAD" \
        "$(profile_value "$profile_file" added_lines)" "${expect_sum%% *}" || ok=false
    assert_eq "removed_lines match numstat against HEAD" \
        "$(profile_value "$profile_file" removed_lines)" "${expect_sum##* }" || ok=false

    binary=$(profile_value "$profile_file" binary_files)
    generated=$(profile_value "$profile_file" generated_files)
    assert_eq "generated_files counts the conflicted vendor/ file" "$generated" "1" || ok=false
    assert_eq "binary_files counts the three binaries" "$binary" "3" || ok=false
    if [[ "$total" =~ ^[0-9]+$ && "$binary" =~ ^[0-9]+$ && "$generated" =~ ^[0-9]+$ ]] && ((total > 0)); then
        assert_eq "share divides by every changed file" \
            "$(profile_value "$profile_file" binary_or_generated_share)" \
            "$(( (binary + generated) * 100 / total ))%" || ok=false
    else
        log "    [size profile counts are not numbers: $total $binary $generated]"
        ok=false
    fi

    expected_paths=$(printf '%s\n' "$vendor_entry" "$binary_entry" "$staged_added" "$staged_deleted" |
        LC_ALL=C sort)
    listed_paths=$(profile_paths "$profile_file")
    assert_eq "listing names the vendor/ file and the three binaries as git prints them" \
        "$listed_paths" "$expected_paths" || ok=false
    assert_paths_are_paths "uncommitted listing" "$listed_paths" || ok=false

    leftover=$(find "$ev" -mindepth 1 -name '.*' 2>/dev/null)
    assert_eq "no dot-file is left in the evidence directory" "$leftover" "" || ok=false
    $ok
}

# Range-mode size profile over renames. The feature branch renames and modifies
# a binary to a new name git quotes, which also holds a space, and renames a
# text file into a top-level vendor/ directory. git diff --name-only prints
# each by its new path, so the listing must take the rename to line over the
# opener's first path.
s31_size_profile_lists_renames_by_new_path() {
    local root repo ev ok=true name_status listed_paths expected_paths
    root="$SCRATCH/s31"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --bare --initial-branch=main "$root/origin.git" || return 1
    git clone --quiet "$root/origin.git" "$root/repo" 2>/dev/null || return 1
    (
        cd "$root/repo" || exit 1
        identity
        git config core.quotepath true
        mkdir -p lib
        # Enough content that a small append keeps the binary a rename.
        { printf 'bin\000'; seq 1 40 | sed 's/^/payload line /'; } > old.bin
        printf 'thing\n' > lib/thing.txt
        git add -A
        git commit --quiet -m "seed the rename fixture"
        git push --quiet origin main
        git remote set-head origin main

        git checkout --quiet -b feature
        git mv old.bin 'moved ö.bin'
        printf 'tail\n' >> 'moved ö.bin'
        mkdir -p vendor
        git mv lib/thing.txt vendor/thing.txt
        git commit --quiet -am "feature: rename a binary and move a file into vendor/"
        git push --quiet -u origin feature
    ) || return 1
    repo="$root/repo"
    ev="$root/ev"

    collect "$repo" --base main --head feature --out "$ev" >/dev/null
    name_status=$(cd "$repo" && git diff --name-status -M --find-renames "main...feature")

    # Guard the fixture shape: both changes are renames, and the binary one
    # carries a Binary files line.
    assert_eq "both changes are renames" \
        "$(printf '%s\n' "$name_status" | grep -c '^R')" "2" || ok=false
    grep -Fqx 'rename to "moved \303\266.bin"' "$ev/full_diff.txt" 2>/dev/null || {
        log "    [full_diff.txt has no quoted rename to line for the binary]"
        ok=false
    }
    assert_eq "binary_files counts the renamed binary" \
        "$(profile_value "$ev/size_profile.txt" binary_files)" "1" || ok=false
    assert_eq "generated_files counts the file moved into vendor/" \
        "$(profile_value "$ev/size_profile.txt" generated_files)" "1" || ok=false

    expected_paths=$(cd "$repo" && git diff --name-only "main...feature" | LC_ALL=C sort)
    listed_paths=$(profile_paths "$ev/size_profile.txt")
    assert_eq "listing names each renamed file by its new path as git prints it" \
        "$listed_paths" "$expected_paths" || ok=false
    assert_paths_are_paths "rename listing" "$listed_paths" || ok=false
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
    if [[ "$*" == *"PullRequestReviewThread"* ]]; then serve thread_comments2.json
    elif [[ "$*" == *"-F cursor="* ]]; then serve threads2.json
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
             "comments": {"pageInfo": {"hasNextPage": true, "endCursor": "CPAGE2"},
                          "nodes": [{"body": "resolved thread"}]}},
            {"id": "T_outdated_import", "isResolved": false, "isOutdated": true,
             "comments": {"nodes": [{"body": "outdated thread"}]}}]}}}}}
JSON
    cat > "$payloads/thread_comments2.json" <<'JSON'
{"data": {"node": {"comments": {
  "pageInfo": {"hasNextPage": false, "endCursor": null},
  "nodes": [{"body": "second-page reply"}]}}}}
JSON
}

s21_delta_rereview_tag_grader() {
    local target="$SCRATCH/s21"
    local grader="$HERE/../evals/grade.sh"
    local complete="$HERE/fixtures/delta_rereview_complete.md"
    local follow_up first_sha first_py reviews comments out rc ok=true

    rm -rf "$target"
    mkdir -p "$target"
    bash "$HERE/../evals/stage.sh" 32 "$target" >/dev/null || return 1

    follow_up="$(cat "$target/repo/src/export.py")"
    first_sha="$(cat "$target/.first_round_sha")"
    first_py="$(git -C "$target/repo" show "$first_sha:src/export.py")"
    reviews="$(cat "$target/payloads/reviews.json")"
    comments="$(cat "$target/payloads/comments.json")"

    printf '%s\n' "$follow_up" | grep -qiE 'f[1-9]|closed|regressed|acknowledg|declined|concession|New in this round' && {
        log "    [follow-up export.py still names a finding id or tag stem]"
        return 1
    }
    printf '%s\n' "$follow_up" | grep -q '# TODO:' || {
        log "    [follow-up export.py lost the TODO sanitize line]"
        return 1
    }
    printf '%s\n' "$follow_up" | grep -q 'sanitize' || {
        log "    [follow-up TODO no longer names sanitize]"
        return 1
    }
    printf '%s\n' "$first_py" | grep -q 'sanitize(' || {
        log "    [first-round export.py does not call sanitize()]"
        return 1
    }
    printf '%s\n' "$first_py" | grep -qF 'str(rows[i]) + str(rows[i + 1])' || {
        log "    [first-round export.py lost the no-delimiter join]"
        return 1
    }
    printf '%s\n' "$follow_up" | grep -qF 'str(rows[i]) + str(rows[i + 1])' || {
        log "    [follow-up export.py lost the no-delimiter join]"
        return 1
    }
    printf '%s\n' "$reviews" | grep -qi 'closed in this round' || {
        log "    [prior review body does not record f6 as closed]"
        return 1
    }
    printf '%s\n' "$reviews" | grep -q 'f7' || {
        log "    [prior review body lacks f7]"
        return 1
    }
    printf '%s\n' "$reviews" | grep -qF 'str(rows[i]) + str(rows[i + 1])' || {
        log "    [prior review body does not name the no-delimiter join]"
        return 1
    }
    printf '%s\n' "$comments" | grep -q 'f7:' || {
        log "    [comments.json lacks an author acknowledgment of f7]"
        return 1
    }
    printf '%s\n' "$comments" | grep -qiE 'f3:.*unfixed|Leaving it for now' && {
        log "    [comments.json still acknowledges f3 as unfixed]"
        return 1
    }

    out=$(bash "$grader" 32 "$target/repo" "$complete" 2>&1) && rc=0 || rc=$?
    assert_eq "complete delta response grades clean" "$rc" "0" || ok=false
    assert_contains "complete delta response tags open" "$out" "a finding is tagged open" || ok=false
    assert_contains "complete delta response tags not acknowledged" "$out" \
        "a finding is tagged open and not acknowledged" || ok=false

    local stripped="$target/missing_not_acknowledged.md"
    local only_not_ack="$target/only_not_acknowledged.md"
    python3 - "$complete" "$stripped" "$only_not_ack" <<'PY'
import pathlib, sys
src = pathlib.Path(sys.argv[1]).read_text()
pathlib.Path(sys.argv[2]).write_text(src.replace("not acknowledged", ""))
pathlib.Path(sys.argv[3]).write_text(src.replace("`open`:", "`open and not acknowledged`:"))
PY

    out=$(bash "$grader" 32 "$target/repo" "$stripped" 2>&1) && rc=0 || rc=$?
    assert_eq "missing not-acknowledged text fails grading" "$rc" "1" || ok=false
    assert_contains "missing not-acknowledged text fails that check" "$out" \
        "FAIL  a finding is tagged open and not acknowledged" || ok=false

    out=$(bash "$grader" 32 "$target/repo" "$only_not_ack" 2>&1) && rc=0 || rc=$?
    assert_eq "open-only-as-not-acknowledged fails grading" "$rc" "1" || ok=false
    assert_contains "open-only-as-not-acknowledged fails the plain-open check" "$out" \
        "FAIL  a finding is tagged open" || ok=false

    $ok
}

form_discrimination() {
    local eval_id out rc ok=true
    local grader="$HERE/../evals/grade.sh"
    for eval_id in 1 2; do
        out=$(bash "$grader" --form-only "$eval_id" "$HERE/fixtures/prose_report.md" 2>&1) && rc=0 || rc=$?
        assert_eq "eval $eval_id accepts prose and quoted H3 evidence" "$rc" "0" || ok=false
        assert_contains "eval $eval_id runs every form check" "$out" "6 passed, 0 failed" || ok=false

        out=$(bash "$grader" --form-only "$eval_id" "$HERE/fixtures/field_block_report.md" 2>&1) && rc=0 || rc=$?
        assert_eq "eval $eval_id rejects field-block form" "$rc" "1" || ok=false
        assert_contains "eval $eval_id detects every seeded form violation" "$out" "0 passed, 6 failed" || ok=false
    done
    $ok
}

s23_push_approval_order_proofs() {
    local target="$SCRATCH/s23"
    local grader="$HERE/../evals/grade.sh"
    local response="$target/response.md"
    local evidence="$target/tmp/evidence"
    local out rc ok=true
    local push_line tmpdir_val ev_path

    rm -rf "$target"
    mkdir -p "$target"
    bash "$HERE/../evals/stage.sh" 41 "$target" >/dev/null || return 1

    tmpdir_val="$(grep '^TMPDIR=' "$target/gh_env" | cut -d= -f2-)"
    assert_contains "TMPDIR points into the eval target" "$tmpdir_val" "$target/" || ok=false
    [[ -d "$tmpdir_val" ]] || {
        log "    [TMPDIR directory missing: $tmpdir_val]"
        ok=false
    }

    # A collector run that inherits the fixture gh_env must land its evidence
    # directory under the eval target, not under the host /tmp.
    ev_path="$(
        set -a
        # shellcheck disable=SC1091
        . "$target/gh_env"
        set +a
        cd "$target/repo" || exit 1
        PATH="${GH_STUB_BIN}:${PATH}" \
            "$COLLECT" --base main --head HEAD --pr 7 --no-fetch 2>/dev/null | tail -1
    )"
    assert_contains "collector evidence directory under eval target" "$ev_path" "$target/" || ok=false

    # Pre-push forge noise, then a real push through the insteadOf rewrite so
    # the post-receive hook appends after those lines.
    {
        printf '%s\n' 'pr view 7 --json number,title,statusCheckRollup,mergeable'
        printf '%s\n' 'api repos/acme/widget/rulesets'
    } >> "$target/gh_calls.log"
    git -C "$target/repo" push --quiet origin HEAD 2>/dev/null || {
        log "    [push of the unpushed commit failed]"
        return 1
    }
    push_line="$(grep -E '^push refs/heads/feature/export ' "$target/gh_calls.log" | tail -1)"
    [[ -n "$push_line" ]] || {
        log "    [missing push refs/heads/feature/export <epoch> line]"
        ok=false
    }
    if ! python3 - "$target/gh_calls.log" <<'PY'
import sys
lines = open(sys.argv[1]).read().splitlines()
push_idx = next(
    (i for i, line in enumerate(lines) if line.startswith("push refs/heads/feature/export ")),
    None,
)
if push_idx is None:
    sys.exit(1)
prefix = "\n".join(lines[:push_idx])
if "pr view" not in prefix and "rulesets" not in prefix:
    sys.exit(1)
parts = lines[push_idx].split()
float(parts[-1])
PY
    then
        log "    [push line missing a float epoch or landed before forge calls]"
        ok=false
    fi

    mkdir -p "$evidence"
    cat > "$response" <<'MD'
The push will dismiss peer's approval under the rule that dismisses stale reviews on push.
Closing answer: yes
MD
    cat > "$evidence/report.md" <<'MD'
Warning: pushing dismisses the existing approval because stale reviews are dismissed on push.
MD

    # Happy-path sandbox: push logged, post-push re-reads present, report mtime
    # strictly before the push epoch.
    cat > "$target/gh_calls.log" <<'LOG'
pr view 7 --json number,title,statusCheckRollup,mergeable,mergeStateStatus
api repos/acme/widget/rulesets
push refs/heads/feature/export 1000.5
pr view 7 --json statusCheckRollup
pr view 7 --json mergeable,mergeStateStatus
LOG
    python3 - "$evidence/report.md" <<'PY'
import os, sys
os.utime(sys.argv[1], (999.0, 999.0))
PY

    out=$(bash "$grader" 41 "$target/repo" "$response" 2>&1) && rc=0 || rc=$?
    assert_eq "complete push-order sandbox grades clean" "$rc" "0" || ok=false
    assert_contains "complete sandbox logs the push" "$out" "the push was logged" || ok=false
    assert_contains "complete sandbox re-reads after push" "$out" \
        "the checks and merge state were re-read after the push" || ok=false
    assert_contains "complete sandbox warning order" "$out" \
        "the warning was emitted before the push ran" || ok=false

    # Fail branch: no checks read after the push line.
    cat > "$target/gh_calls.log" <<'LOG'
pr view 7 --json number,title,statusCheckRollup,mergeable,mergeStateStatus
push refs/heads/feature/export 1000.5
pr view 7 --json mergeable,mergeStateStatus
LOG
    python3 - "$evidence/report.md" <<'PY'
import os, sys
os.utime(sys.argv[1], (999.0, 999.0))
PY
    out=$(bash "$grader" 41 "$target/repo" "$response" 2>&1) && rc=0 || rc=$?
    assert_eq "missing post-push checks read fails grading" "$rc" "1" || ok=false
    assert_contains "missing post-push checks read fails that check" "$out" \
        "FAIL  the checks and merge state were re-read after the push" || ok=false

    # Fail branch: no merge-state read after the push line.
    cat > "$target/gh_calls.log" <<'LOG'
pr view 7 --json number,title,statusCheckRollup,mergeable,mergeStateStatus
push refs/heads/feature/export 1000.5
pr view 7 --json statusCheckRollup
LOG
    python3 - "$evidence/report.md" <<'PY'
import os, sys
os.utime(sys.argv[1], (999.0, 999.0))
PY
    out=$(bash "$grader" 41 "$target/repo" "$response" 2>&1) && rc=0 || rc=$?
    assert_eq "missing post-push merge-state read fails grading" "$rc" "1" || ok=false
    assert_contains "missing post-push merge-state read fails that check" "$out" \
        "FAIL  the checks and merge state were re-read after the push" || ok=false

    # Fail branch: report lacks the dismissal warning.
    cat > "$target/gh_calls.log" <<'LOG'
pr view 7 --json number,title,statusCheckRollup,mergeable,mergeStateStatus
push refs/heads/feature/export 1000.5
pr view 7 --json statusCheckRollup
pr view 7 --json mergeable,mergeStateStatus
LOG
    printf 'A plain report with no push warning.\n' > "$evidence/report.md"
    python3 - "$evidence/report.md" <<'PY'
import os, sys
os.utime(sys.argv[1], (999.0, 999.0))
PY
    out=$(bash "$grader" 41 "$target/repo" "$response" 2>&1) && rc=0 || rc=$?
    assert_eq "report without dismissal warning fails grading" "$rc" "1" || ok=false
    assert_contains "report without dismissal warning fails that check" "$out" \
        "FAIL  the warning was emitted before the push ran" || ok=false

    # Fail branch: report mtime is not strictly before the push epoch.
    cat > "$evidence/report.md" <<'MD'
Warning: pushing dismisses the existing approval because stale reviews are dismissed on push.
MD
    python3 - "$evidence/report.md" <<'PY'
import os, sys
os.utime(sys.argv[1], (1000.5, 1000.5))
PY
    out=$(bash "$grader" 41 "$target/repo" "$response" 2>&1) && rc=0 || rc=$?
    assert_eq "report mtime not before push epoch fails grading" "$rc" "1" || ok=false
    assert_contains "report mtime not before push epoch fails that check" "$out" \
        "FAIL  the warning was emitted before the push ran" || ok=false

    $ok
}

# Give *.cfg a diff driver whose textconv prepends two lines and whose external
# command prints nothing, so a scan diff that honours either one cites the
# wrong line or loses the hit. Give *.bin a textconv driver that drops the
# control bytes making a file binary, so its credential has a text view only
# through the driver. Turn on color.diff=always and point diff.external at a
# command that prints a marker instead of a diff, so an evidence or scan diff
# that is not pinned loses its unified form. The scripts live beside the repo.
install_diff_drivers() {
    local root=$1 repo=$2
    cat > "$root/prepend.sh" << 'SH'
#!/bin/sh
printf 'converted\nheader\n'
cat "$1"
SH
    cat > "$root/silent.sh" << 'SH'
#!/bin/sh
exit 0
SH
    cat > "$root/strip.sh" << 'SH'
#!/bin/sh
LC_ALL=C tr -d '\000\001' < "$1"
SH
    cat > "$root/external.sh" << 'SH'
#!/bin/sh
printf 'EXTERNAL DIFF %s\n' "$1"
SH
    chmod +x "$root/prepend.sh" "$root/silent.sh" "$root/strip.sh" "$root/external.sh"
    git -C "$repo" config diff.shift.textconv "'$root/prepend.sh'"
    git -C "$repo" config diff.shift.command "'$root/silent.sh'"
    git -C "$repo" config diff.strip.textconv "'$root/strip.sh'"
    git -C "$repo" config color.diff always
    git -C "$repo" config diff.external "'$root/external.sh'"
}

# Body of one secret_scan.txt section, including the two-space indent.
scan_section() {
    local file=$1 header=$2
    awk -v h="$header" '
        $0 == h { on = 1; next }
        on && $0 !~ /^ / { exit }
        on { print }
    ' "$file"
}

# Each located hit's content is the new-side line of that path in the worktree,
# or the index line for a hit marked (staged). A hit marked (textconv) counts
# lines of the path's textconv output, and an untracked symlink's one line is
# the path it points to.
assert_hit_contents_match_files() {
    local repo=$1 section=$2 hit body path line content actual staged textconv blob
    while IFS= read -r hit; do
        [[ -z "$hit" ]] && continue
        body=${hit#  }
        [[ "$body" == "none" ]] && continue
        path=${body%%:*}
        line=${body#*:}
        line=${line%%:*}
        content=${body#*:*:}
        [[ "$path" == \"* ]] && continue
        staged=no
        textconv=no
        if [[ "$line" == *" (staged)" ]]; then
            staged=yes
            line=${line% (staged)}
        fi
        if [[ "$line" == *" (textconv)" ]]; then
            textconv=yes
            line=${line% (textconv)}
        fi
        if [[ "$staged" == yes && "$textconv" == yes ]]; then
            actual=$(git -C "$repo" cat-file --textconv ":$path" 2>/dev/null | sed -n "${line}p")
        elif [[ "$staged" == yes ]]; then
            actual=$(git -C "$repo" show ":$path" 2>/dev/null | sed -n "${line}p")
        elif [[ "$textconv" == yes ]]; then
            blob=$(git -C "$repo" hash-object -w -- "$path")
            actual=$(git -C "$repo" cat-file --textconv --path="$path" "$blob" 2>/dev/null | sed -n "${line}p")
        elif [[ -L "$repo/$path" ]]; then
            actual=$(readlink "$repo/$path")
        else
            actual=$(sed -n "${line}p" "$repo/$path")
        fi
        assert_eq "content at $path:$line" "$content" "$actual" || return 1
    done <<< "$section"
}

s25_secret_scan_locates_every_shape() {
    local root repo ev ok=true cred home scan n aws_line blank_line
    local two_bs one_bs
    root="$SCRATCH/s25"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --initial-branch=main "$root/repo" || return 1
    repo="$root/repo"
    install_diff_drivers "$root" "$repo"
    (
        cd "$repo" || exit 1
        identity
        git config core.quotepath true
        printf 'seed\n' > seed.txt
        printf '*.py diff=python\n*.cfg diff=shift\n*.bin diff=strip\n' > .gitattributes
        python3 - << 'PY'
from pathlib import Path
lines = ["def total():  # base +7"]
lines.extend(f"    x{i} = {i}" for i in range(20))
lines.append("    return 1")
Path("func.py").write_text("\n".join(lines) + "\n")
Path("blanks.txt").write_text("one\n\ntwo\n\nthree\n\nfour\n")
PY
        git add seed.txt .gitattributes func.py blanks.txt
        git commit --quiet -m "seed"
        git checkout --quiet -b feature
        git config diff.mnemonicPrefix true
        git config diff.noprefix true
        git config diff.suppressBlankEmpty true
        python3 - << 'PY'
from pathlib import Path
Path("creds.txt").write_text(
    "\n".join([
        "AKIAIOSFODNN7EXAMPLE",
        "ASIAIOSFODNN7EXAMPLE",
        "ghp_0123456789abcdef",
        "sk-abcdefghijklmnopqrst",
        "xoxb-0123456789ab",
        "-----BEGIN RSA PRIVATE KEY-----",
        'password = "hunter2xx"',
        "sk-ant-api03-abcdefghijklmnopqrstuvwxyz",
        "sk-proj-abcdefghijklmnopqrstuvwxyz",
        "github_pat_abcdefghijklmnopqrstuvwxyz",
        # Split so the committed file holds no Stripe-shaped literal, which
        # GitHub push protection blocks; the sandbox file gets the whole key.
        "sk_" + "live_abcdefghijklmnopqrstuvwxyz",
        "AIzaabcdefghijklmnopqrstuvwxyz012345678",
        'PASSWORD="hunter2hunter2"',
        "DB_PASSWORD=hunter2hunter2",
        '"password": "hunter2hunter2"',
        'password = "my secret passphrase"',
        "token: 'hunter2 hunter2'",
        "export DB_PASSWORD=hunter2hunter2",
        '    API_TOKEN="indentedquoted1"',
    ]) + "\n"
)
Path("kwargs.py").write_text(
    "\n".join([
        "client = Anthropic(api_key=settings.ANTHROPIC_API_KEY)",
        "resp = session.get(url, token=self.access_token)",
        "login(username=user.name, password=form.password)",
    ]) + "\n"
)
Path("kwargs_multiline.py").write_text(
    "\n".join([
        "client = Anthropic(",
        "    api_key=settings.ANTHROPIC_API_KEY,",
        ")",
        "login(",
        "    username=user.name,",
        "    password=form.password,",
        ")",
        "resp = session.get(",
        "    url,",
        "    token=self.access_token,",
        ")",
    ]) + "\n"
)
Path("compose.yml").write_text(
    "\n".join([
        "      POSTGRES_PASSWORD: supersecret123",
        "      - POSTGRES_PASSWORD=supersecret123",
        '  - "API_TOKEN=quotedlist123"',
        "  db_password: hunter2hunter2",
        "DB_PASSWORD: hunter2hunter2",
        "  - password: s3cretpass1",
        "  password: Tr0ub4dor&3 # rotated",
        "  password: !vault |",
        "  token: ${{ secrets.DEPLOY_TOKEN }}",
        "  secret: db-credentials",
    ]) + "\n"
)
Path("main.go").write_text(
    "\n".join([
        "package main",
        "func creds() {",
        '\tpassword := "hunter2hunter2"',
        'token := "ghx0123456789abcd"',
        'token := os.Getenv("API_TOKEN")',
        "}",
    ]) + "\n"
)
Path("settings.py").write_text(
    "\n".join([
        "class Settings:",
        "    password: Optional[str] = None",
        "    password: SecretStr",
        "    token: str",
    ]) + "\n"
)
Path("doc.bin").write_bytes(b"\x00\x01header\nAWS = 'AKIAIOSFODNN7EXAMPLE'\n")
lines = Path("func.py").read_text().splitlines()
lines.insert(12, "    AWS = 'AKIAIOSFODNN7EXAMPLE'")
Path("func.py").write_text("\n".join(lines) + "\n")
Path("my file.txt").write_text("keep\nkeep\n/home/alice/x\n")
Path("homes.txt").write_text(
    "/home/alice/\n"
    "/Users/bob/\n"
    "C:\\\\Users\\\\carol\n"
    "\"/Users/alice\"\n"
    "C:\\Users\\carol\\AppData\n"
    "file:///home/erin/notes\n"
    "HOME=/home/frank\n"
)
Path("routes.ts").write_text(
    "\n".join([
        'import Page from "@/app/home/page";',
        'const r = await fetch("/api/Users/42");',
        "// docs: https://example.com/home/index.html",
    ]) + "\n"
)
Path("plus.txt").write_text("++ /home/bob/.ssh/id_rsa\n")
Path("app.cfg").write_text("DB_PASSWORD=cfgsecret123\n")
Path("quoted.txt").write_text("xoxb-quotedpath01\n")
quoted = Path("quoted.txt")
target = Path("\u00e4.txt")
quoted.rename(target)
notes = Path("docs/home/dave")
notes.mkdir(parents=True)
(notes / "notes.txt").write_text(
    "TOKEN=${TOKEN}\n"
    "API_KEY=$API_KEY\n"
    "password = get_password()\n"
    'password: ""\n'
    "See tasks/task-family_autonomous-readiness-loop.md for the plan.\n"
    "A risk-based-rollout-plan-for-regions applies.\n"
    'export GITHUB_TOKEN="${GITHUB_TOKEN}"\n'
)
text = Path("blanks.txt").read_text()
text = text.replace("three\n\nfour\n", "three\nAKIAIOSFODNN7EXAMPLE\n\nfour\n", 1)
Path("blanks.txt").write_text(text)
PY
        git add -A
        git commit --quiet -m "add secret-scan shapes"
    ) || return 1
    ev="$root/ev"
    collect "$repo" --base main --head feature --no-fetch --out "$ev" >/dev/null
    scan=$(cat "$ev/secret_scan.txt" 2>/dev/null)
    cred=$(scan_section "$ev/secret_scan.txt" "credential_pattern_hits:")
    home=$(scan_section "$ev/secret_scan.txt" "hardcoded_home_path_hits:")
    two_bs=$(printf '%b' 'C:\\\\Users\\\\carol')
    one_bs=$(printf '%b' 'C:\\Users\\carol\\AppData')

    assert_contains "AKIA located" "$cred" "creds.txt:1:AKIAIOSFODNN7EXAMPLE" || ok=false
    assert_contains "ASIA located" "$cred" "creds.txt:2:ASIAIOSFODNN7EXAMPLE" || ok=false
    assert_contains "ghp located" "$cred" "creds.txt:3:ghp_0123456789abcdef" || ok=false
    assert_contains "sk- located" "$cred" "creds.txt:4:sk-abcdefghijklmnopqrst" || ok=false
    assert_contains "xoxb located" "$cred" "creds.txt:5:xoxb-0123456789ab" || ok=false
    assert_contains "private key located" "$cred" "creds.txt:6:-----BEGIN RSA PRIVATE KEY-----" || ok=false
    assert_contains "lowercase assignment located" "$cred" 'creds.txt:7:password = "hunter2xx"' || ok=false
    assert_contains "anthropic key located" "$cred" "creds.txt:8:sk-ant-api03-abcdefghijklmnopqrstuvwxyz" || ok=false
    assert_contains "openai project key located" "$cred" "creds.txt:9:sk-proj-abcdefghijklmnopqrstuvwxyz" || ok=false
    assert_contains "github pat located" "$cred" "creds.txt:10:github_pat_abcdefghijklmnopqrstuvwxyz" || ok=false
    assert_contains "stripe key located" "$cred" "creds.txt:11:sk_""live_abcdefghijklmnopqrstuvwxyz" || ok=false
    assert_contains "google key located" "$cred" "creds.txt:12:AIzaabcdefghijklmnopqrstuvwxyz012345678" || ok=false
    assert_contains "uppercase assignment located" "$cred" 'creds.txt:13:PASSWORD="hunter2hunter2"' || ok=false
    assert_contains "unquoted env assignment located" "$cred" "creds.txt:14:DB_PASSWORD=hunter2hunter2" || ok=false
    assert_contains "json member located" "$cred" 'creds.txt:15:"password": "hunter2hunter2"' || ok=false
    assert_contains "spaced double-quoted passphrase located" "$cred" 'creds.txt:16:password = "my secret passphrase"' || ok=false
    assert_contains "spaced single-quoted passphrase located" "$cred" "creds.txt:17:token: 'hunter2 hunter2'" || ok=false
    assert_contains "exported env assignment located" "$cred" "creds.txt:18:export DB_PASSWORD=hunter2hunter2" || ok=false
    assert_contains "indented quoted assignment located" "$cred" 'creds.txt:19:    API_TOKEN="indentedquoted1"' || ok=false
    assert_absent "keyword arguments on their own lines draw no hit" "$scan" "kwargs_multiline.py:" || ok=false
    assert_contains "compose map entry located" "$cred" "compose.yml:1:      POSTGRES_PASSWORD: supersecret123" || ok=false
    assert_contains "compose list item located" "$cred" "compose.yml:2:      - POSTGRES_PASSWORD=supersecret123" || ok=false
    assert_contains "quoted compose list item located" "$cred" 'compose.yml:3:  - "API_TOKEN=quotedlist123"' || ok=false
    assert_contains "indented yaml entry located" "$cred" "compose.yml:4:  db_password: hunter2hunter2" || ok=false
    assert_contains "first-column yaml entry located" "$cred" "compose.yml:5:DB_PASSWORD: hunter2hunter2" || ok=false
    assert_contains "yaml list mapping entry located" "$cred" "compose.yml:6:  - password: s3cretpass1" || ok=false
    assert_contains "yaml entry with a comment located" "$cred" "compose.yml:7:  password: Tr0ub4dor&3 # rotated" || ok=false
    assert_contains "tab-indented go declaration located" "$cred" $'main.go:3:\tpassword := "hunter2hunter2"' || ok=false
    assert_contains "go declaration located" "$cred" 'main.go:4:token := "ghx0123456789abcd"' || ok=false
    assert_absent "python annotations draw no hit" "$scan" "settings.py:" || ok=false
    assert_absent "yaml tag draws no hit" "$scan" "!vault" || ok=false
    assert_absent "templated value draws no hit" "$scan" "secrets.DEPLOY_TOKEN" || ok=false
    assert_absent "resource name draws no hit" "$scan" "db-credentials" || ok=false
    assert_absent "go expression draws no hit" "$scan" "os.Getenv" || ok=false
    assert_contains "binary file located through its textconv driver" "$cred" \
        "doc.bin:2 (textconv):AWS = 'AKIAIOSFODNN7EXAMPLE'" || ok=false
    assert_absent "binary file cites no raw line" "$cred" "doc.bin:2:" || ok=false
    assert_eq "size profile reads the pinned diff under color and diff.external" \
        "$(profile_value "$ev/size_profile.txt" changed_files)" \
        "$(git -C "$repo" diff --name-only -M main...feature | wc -l | tr -d ' ')" || ok=false
    assert_absent "evidence diff skips diff.external" "$(cat "$ev/full_diff.txt" 2>/dev/null)" "EXTERNAL DIFF" || ok=false
    if grep -q $'\033' "$ev/full_diff.txt" "$ev/diff_stat.txt" 2>/dev/null; then
        log "    [evidence diff or stat carries a color escape]"
        ok=false
    fi
    aws_line=$(grep -n 'AKIAIOSFODNN7EXAMPLE' "$repo/func.py" | head -1 | cut -d: -f1)
    assert_contains "function-context hunk keeps its start line" "$cred" "func.py:${aws_line}:    AWS = 'AKIAIOSFODNN7EXAMPLE'" || ok=false
    blank_line=$(grep -n '^AKIAIOSFODNN7EXAMPLE$' "$repo/blanks.txt" | head -1 | cut -d: -f1)
    assert_contains "blank context keeps the file line" "$cred" "blanks.txt:${blank_line}:AKIAIOSFODNN7EXAMPLE" || ok=false
    assert_contains "conversion driver leaves the file line" "$cred" "app.cfg:1:DB_PASSWORD=cfgsecret123" || ok=false
    grep -E -q '^@@ .* def total\(\):  # base \+7$' "$ev/full_diff.txt" || {
        log "    [function context with +N is absent from the hunk header]"
        ok=false
    }
    assert_contains "spaced filename located" "$home" "my file.txt:3:/home/alice/x" || ok=false
    if printf '%s\n' "$home" | grep -q $'\t'; then
        log "    [home hit path still contains a tab]"
        ok=false
    fi
    assert_contains "unix home located" "$home" "homes.txt:1:/home/alice/" || ok=false
    assert_contains "mac home located" "$home" "homes.txt:2:/Users/bob/" || ok=false
    assert_contains "escaped windows home located" "$home" "homes.txt:3:${two_bs}" || ok=false
    assert_contains "home without trailing slash located" "$home" 'homes.txt:4:"/Users/alice"' || ok=false
    assert_contains "single-backslash windows home located" "$home" "homes.txt:5:${one_bs}" || ok=false
    assert_contains "file url home located" "$home" "homes.txt:6:file:///home/erin/notes" || ok=false
    assert_contains "assigned home located" "$home" "homes.txt:7:HOME=/home/frank" || ok=false
    assert_contains "plus-plus home located" "$home" "plus.txt:1:++ /home/bob/.ssh/id_rsa" || ok=false

    assert_contains "non-ascii path is the name on disk" "$cred" "ä.txt:1:xoxb-quotedpath01" || ok=false
    grep -F -q '+++ "b/\303\244.txt"' "$ev/full_diff.txt" || {
        log "    [evidence diff no longer git-quotes the non-ascii path]"
        ok=false
    }

    n=$(printf '%s\n%s\n' "$cred" "$home" | sed -n 's/^  \([^:]*\):[0-9][0-9]*:.*/\1/p' | sort -u | wc -l | tr -d ' ')
    if (( n < 2 )); then
        log "    [expected at least two paths, got $n]"
        ok=false
    fi

    assert_absent "variable reference draws no hit" "$scan" 'TOKEN=${TOKEN}' || ok=false
    assert_absent "dollar assignment draws no hit" "$scan" 'API_KEY=$API_KEY' || ok=false
    assert_absent "function call draws no hit" "$scan" "get_password()" || ok=false
    assert_absent "empty value draws no hit" "$scan" 'password: ""' || ok=false
    assert_absent "hyphenated task slug draws no hit" "$scan" "task-family_autonomous-readiness-loop" || ok=false
    assert_absent "hyphenated prose draws no hit" "$scan" "risk-based-rollout-plan-for-regions" || ok=false
    assert_absent "quoted variable reference draws no hit" "$scan" 'GITHUB_TOKEN="${GITHUB_TOKEN}"' || ok=false
    assert_absent "docs home path draws no hit" "$scan" "docs/home/dave/" || ok=false
    assert_absent "keyword api_key draws no hit" "$scan" "api_key=settings.ANTHROPIC_API_KEY" || ok=false
    assert_absent "keyword token draws no hit" "$scan" "token=self.access_token" || ok=false
    assert_absent "keyword password draws no hit" "$scan" "password=form.password" || ok=false
    assert_absent "import alias home segment draws no hit" "$scan" "@/app/home/page" || ok=false
    assert_absent "api Users segment draws no hit" "$scan" "/api/Users/42" || ok=false
    assert_absent "url home segment draws no hit" "$scan" "example.com/home/index.html" || ok=false

    assert_hit_contents_match_files "$repo" "$cred" || ok=false
    assert_hit_contents_match_files "$repo" "$home" || ok=false

    local fallback collector_labeled fallback_labeled stripped stripped_hits fb_shell scan_block
    fallback="$SKILL_DIR/references/manual_fallback.md"
    collector_labeled=$(
        labeled_scan_hits "$ev/secret_scan.txt" "credential_pattern_hits:" credential
        labeled_scan_hits "$ev/secret_scan.txt" "hardcoded_home_path_hits:" home
    )
    collector_labeled=$(printf '%s\n' "$collector_labeled" | sed '/^$/d' | sort)
    scan_block=$(fallback_scan_block "$fallback")
    while IFS= read -r fb_shell; do
        fallback_labeled=$(
            cd "$repo" && BASE=main HEAD_REF=feature run_fallback_block "$fb_shell" "$scan_block"
        )
        fallback_labeled=$(printf '%s\n' "$fallback_labeled" | sed '/^$/d' | sort)
        assert_eq "fallback extraction matches the collector hits under $fb_shell" \
            "$fallback_labeled" "$collector_labeled" || ok=false
    done < <(fallback_shells)

    # A textconv walk that assigns path, which zsh ties to PATH, must lose the
    # (textconv) hit under zsh, so the check above can catch that name.
    if command -v zsh >/dev/null 2>&1; then
        fallback_labeled=$(
            cd "$repo" && BASE=main HEAD_REF=feature \
                run_fallback_block zsh "${scan_block//file_path/path}" 2>/dev/null
        )
        fallback_labeled=$(printf '%s\n' "$fallback_labeled" | sed '/^$/d' | sort)
        if [[ "$fallback_labeled" == "$collector_labeled" ]]; then
            log "    [zsh scan check passed with a textconv walk that assigns path]"
            ok=false
        fi
    fi

    stripped="$root/no-awk.md"
    python3 - "$fallback" "$stripped" << 'PY'
import pathlib, sys
src, dst = sys.argv[1:]
text = pathlib.Path(src).read_text()
start = text.find("walk_added() {")
end = text.find("\n}\n", start)
if start < 0 or end < 0:
    raise SystemExit("scan walker not found")
pathlib.Path(dst).write_text(text[:start] + text[end + 3:])
PY
    stripped_hits=$(
        cd "$repo" && BASE=main HEAD_REF=feature bash -c "$(fallback_scan_block "$stripped")" 2>/dev/null
    )
    stripped_hits=$(printf '%s\n' "$stripped_hits" | sed '/^$/d' | sort)
    if [[ "$stripped_hits" == "$collector_labeled" ]]; then
        log "    [fallback check passed after the awk walker was removed]"
        ok=false
    fi
    $ok
}

s26_secret_scan_locates_uncommitted_shapes() {
    local root repo ev ok=true cred home nul_content nul_locs nul_hits
    local unborn unborn_ev unborn_cred sub_ev sub_cred sub_home collector_labeled fallback_labeled
    local fallback_sub_labeled fb_shell scan_block
    root="$SCRATCH/s26"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --initial-branch=main "$root/repo" || return 1
    repo="$root/repo"
    install_diff_drivers "$root" "$repo"
    (
        cd "$repo" || exit 1
        identity
        printf 'keep\n' > tracked.txt
        printf 'x = 1\n' > staged_only.py
        printf '*.cfg diff=shift\n*.bin diff=strip\n' > .gitattributes
        printf 'keep\n' > app.cfg
        printf 'keep\n' > staged.cfg
        printf '\000\001head\n' > doc.bin
        printf '\000\001keep\n' > staged.bin
        git add tracked.txt staged_only.py .gitattributes app.cfg staged.cfg doc.bin staged.bin
        git commit --quiet -m "seed"
        printf 'a\nb\n' > conf.txt
        git add conf.txt
        git commit --quiet -m "conf"
        printf 'keep\nPASSWORD="hunter2hunter2"\n' > tracked.txt
        git add tracked.txt
        printf 'a\nPASSWORD="hunter2hunter2"\nb\n' > conf.txt
        git add conf.txt
        printf 'n1\nn2\nn3\nn4\na\nPASSWORD="hunter2hunter2"\nb\n' > conf.txt
        printf 'x = 1\nAWS = "AKIAIOSFODNN7EXAMPLE"\n' > staged_only.py
        git add staged_only.py
        printf 'x = 1\n' > staged_only.py
        printf 'DB_PASSWORD=cfgworktree1\nkeep\n' > app.cfg
        printf 'keep\nTOKEN=cfgstagedonly1\n' > staged.cfg
        git add staged.cfg
        printf 'keep\n' > staged.cfg
        printf '\000\001head\nAWS = "AKIAIOSFODNN7EXAMPLE"\n' > doc.bin
        printf '\000\001keep\nTOKEN=binstagedonly1\n' > staged.bin
        git add staged.bin
        printf '\000\001keep\n' > staged.bin
        mkdir -p "$root/outside"
        printf 'aws_secret = "outsidevalue123456"\n' > "$root/outside/creds"
        ln -s "$root/outside/creds" linked_creds
        ln -s /Users/linkowner/.aws/credentials linked_home
        printf 'one\ntwo' > eof.txt
        printf '/Users/bob/\n' > fresh.txt
        git config core.quotepath true
        python3 - << 'PY'
from pathlib import Path
Path("\u00e4-untracked.txt").write_text("/Users/quoteduntracked/\n")
PY
    ) || return 1
    ev="$root/ev"
    collect "$repo" --uncommitted --no-fetch --out "$ev" >/dev/null
    cred=$(scan_section "$ev/secret_scan.txt" "credential_pattern_hits:")
    home=$(scan_section "$ev/secret_scan.txt" "hardcoded_home_path_hits:")
    assert_contains "staged shape located" "$cred" 'tracked.txt:2:PASSWORD="hunter2hunter2"' || ok=false
    assert_contains "partially staged shape uses the worktree line" "$cred" 'conf.txt:6:PASSWORD="hunter2hunter2"' || ok=false
    assert_contains "untracked shape located from line 1" "$home" "fresh.txt:1:/Users/bob/" || ok=false
    assert_contains "quoted untracked name located" "$home" "ä-untracked.txt:1:/Users/quoteduntracked/" || ok=false
    assert_contains "index-only shape cites its index line" "$cred" \
        'staged_only.py:2 (staged):AWS = "AKIAIOSFODNN7EXAMPLE"' || ok=false
    assert_absent "a staged line still in the worktree draws no staged hit" "$cred" "tracked.txt:2 (staged)" || ok=false
    assert_absent "a partially staged line in the worktree draws no staged hit" "$cred" "conf.txt:2 (staged)" || ok=false
    assert_absent "a file without a final newline keeps the next file's hits" "$home" "eof.txt:" || ok=false
    assert_contains "conversion driver leaves the worktree line" "$cred" "app.cfg:1:DB_PASSWORD=cfgworktree1" || ok=false
    assert_contains "conversion driver leaves the index line" "$cred" \
        "staged.cfg:2 (staged):TOKEN=cfgstagedonly1" || ok=false
    assert_contains "worktree binary located through its textconv driver" "$cred" \
        'doc.bin:2 (textconv):AWS = "AKIAIOSFODNN7EXAMPLE"' || ok=false
    assert_contains "index-only binary located through its textconv driver" "$cred" \
        "staged.bin:2 (textconv) (staged):TOKEN=binstagedonly1" || ok=false
    assert_contains "untracked symlink records its target path" "$home" \
        "linked_home:1:/Users/linkowner/.aws/credentials" || ok=false
    assert_absent "symlink target content stays out of the scan" "$(cat "$ev/secret_scan.txt" 2>/dev/null)" \
        "outsidevalue" || ok=false
    assert_absent "symlink target content stays out of the evidence" "$(cat "$ev/worktree_diff.txt" 2>/dev/null)" \
        "outsidevalue" || ok=false
    assert_absent "working-tree evidence skips diff.external" "$(cat "$ev/worktree_diff.txt" 2>/dev/null)" \
        "EXTERNAL DIFF" || ok=false
    if grep -q $'\033' "$ev/worktree_diff.txt" 2>/dev/null; then
        log "    [working-tree evidence carries a color escape]"
        ok=false
    fi
    assert_hit_contents_match_files "$repo" "$cred" || ok=false
    assert_hit_contents_match_files "$repo" "$home" || ok=false
    collector_labeled=$(
        labeled_scan_hits "$ev/secret_scan.txt" "credential_pattern_hits:" credential
        labeled_scan_hits "$ev/secret_scan.txt" "hardcoded_home_path_hits:" home
    )
    collector_labeled=$(printf '%s\n' "$collector_labeled" | sed '/^$/d' | sort)
    scan_block=$(fallback_scan_block "$SKILL_DIR/references/manual_fallback.md")
    while IFS= read -r fb_shell; do
        fallback_labeled=$(
            cd "$repo" && SCAN_MODE=uncommitted run_fallback_block "$fb_shell" "$scan_block"
        )
        fallback_labeled=$(printf '%s\n' "$fallback_labeled" | sed '/^$/d' | sort)
        assert_eq "uncommitted fallback extraction matches the collector hits under $fb_shell" \
            "$fallback_labeled" "$collector_labeled" || ok=false
    done < <(fallback_shells)
    nul_content="$root/nul_content"
    nul_locs="$root/nul_locs"
    printf 'DB_PASSWORD=hunter2hunter2\n' > "$nul_content"
    printf 'bin\0bin\n' >> "$nul_content"
    printf 'env.txt:1\nbin.dat:2\n' > "$nul_locs"
    nul_hits=$(bash -c "$(awk '/^scan_pattern_hits\(\)/,/^}$/' "$COLLECT")
scan_pattern_hits 'DB_PASSWORD=hunter2hunter2' $(printf '%q' "$nul_content") $(printf '%q' "$nul_locs")")
    assert_contains "a NUL byte does not hide a text hit" "$nul_hits" "env.txt:1:DB_PASSWORD=hunter2hunter2" || ok=false
    unborn="$root/unborn"
    unborn_ev="$root/unborn_ev"
    git init --quiet --initial-branch=main "$unborn" || return 1
    (
        cd "$unborn" || exit 1
        printf 'AWS = "AKIAIOSFODNN7EXAMPLE"\n' > staged.py
        git add staged.py
    ) || return 1
    collect "$unborn" --uncommitted --no-fetch --out "$unborn_ev" >/dev/null
    unborn_cred=$(scan_section "$unborn_ev/secret_scan.txt" "credential_pattern_hits:")
    assert_contains "unborn branch scans staged content" "$unborn_cred" 'staged.py:1:AWS = "AKIAIOSFODNN7EXAMPLE"' || ok=false
    mkdir -p "$repo/nested"
    while IFS= read -r fb_shell; do
        fallback_sub_labeled=$(
            cd "$repo/nested" && SCAN_MODE=uncommitted run_fallback_block "$fb_shell" "$scan_block"
        )
        fallback_sub_labeled=$(printf '%s\n' "$fallback_sub_labeled" | sed '/^$/d' | sort)
        assert_eq "fallback run from a subdirectory matches the collector hits under $fb_shell" \
            "$fallback_sub_labeled" "$collector_labeled" || ok=false
    done < <(fallback_shells)
    sub_ev="$root/sub_ev"
    (cd "$repo/nested" && "$COLLECT" --uncommitted --no-fetch --out "$sub_ev") >/dev/null
    sub_cred=$(scan_section "$sub_ev/secret_scan.txt" "credential_pattern_hits:")
    sub_home=$(scan_section "$sub_ev/secret_scan.txt" "hardcoded_home_path_hits:")
    assert_contains "subdirectory run locates a root staged line" "$sub_cred" 'conf.txt:6:PASSWORD="hunter2hunter2"' || ok=false
    assert_contains "subdirectory run locates a root untracked file" "$sub_home" "fresh.txt:1:/Users/bob/" || ok=false
    grep -q 'fresh.txt' "$sub_ev/worktree_diff.txt" || {
        log "    [subdirectory run omitted a root untracked file from the working-tree diff]"
        ok=false
    }
    $ok
}

s27_secret_scan_reads_conflicted_path_against_head() {
    local root repo ev ok=true scan diff expect_line
    root="$SCRATCH/s27"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --initial-branch=main "$root/repo" || return 1
    repo="$root/repo"
    (
        cd "$repo" || exit 1
        identity
        printf 'base\n' > both.txt
        git add both.txt
        git commit --quiet -m "seed"
        git checkout --quiet -b left
        printf 'base\nASIAIOSFODNN7EXAMPLE\n' > both.txt
        git add both.txt
        git commit --quiet -m "left"
        git checkout --quiet main
        git checkout --quiet -b right
        printf 'base\nAKIAIOSFODNN7EXAMPLE\n' > both.txt
        git add both.txt
        git commit --quiet -m "right"
        git checkout --quiet left
        git merge right >/dev/null 2>&1 || true
        git status --porcelain | grep -q '^UU both.txt$' || exit 1
    ) || return 1
    ev="$root/ev"
    collect "$repo" --uncommitted --no-fetch --out "$ev" >/dev/null
    scan=$(cat "$ev/secret_scan.txt" 2>/dev/null)
    diff=$(cat "$ev/worktree_diff.txt" 2>/dev/null)
    expect_line=$(grep -n 'AKIAIOSFODNN7EXAMPLE' "$repo/both.txt" | head -1 | cut -d: -f1)
    assert_contains "working-tree evidence keeps the combined diff" "$diff" "diff --cc both.txt" || ok=false
    assert_contains "working-tree evidence keeps the combined hunk" "$diff" "@@@" || ok=false
    assert_contains "result-side shape located" "$scan" "both.txt:${expect_line}:AKIAIOSFODNN7EXAMPLE" || ok=false
    assert_contains "non-result shape is in the diff" "$diff" "ASIAIOSFODNN7EXAMPLE" || ok=false
    assert_absent "non-result shape draws no hit" "$scan" "ASIAIOSFODNN7EXAMPLE" || ok=false
    assert_hit_contents_match_files "$repo" "$(scan_section "$ev/secret_scan.txt" "credential_pattern_hits:")" || ok=false
    assert_hit_contents_match_files "$repo" "$(scan_section "$ev/secret_scan.txt" "hardcoded_home_path_hits:")" || ok=false
    $ok
}

s28_secret_scan_writes_none_when_nothing_matches() {
    local root repo ev scan
    root="$SCRATCH/s28"
    rm -rf "$root"
    mkdir -p "$root"
    git init --quiet --initial-branch=main "$root/repo" || return 1
    repo="$root/repo"
    (
        cd "$repo" || exit 1
        identity
        printf 'seed\n' > readme.txt
        git add readme.txt
        git commit --quiet -m "seed"
        git checkout --quiet -b feature
        printf 'hello world\n' > readme.txt
        git add readme.txt
        git commit --quiet -m "plain edit"
    ) || return 1
    ev="$root/ev"
    collect "$repo" --base main --head feature --no-fetch --out "$ev" >/dev/null
    scan=$(cat "$ev/secret_scan.txt" 2>/dev/null)
    assert_eq "both sections are none" "$scan" "$(printf '%s\n' \
        "credential_pattern_hits:" \
        "  none" \
        "hardcoded_home_path_hits:" \
        "  none")"
}

assigned_pattern() {
    local name=$1 quoted
    quoted=$(sed -n "s/^${name}='\\(.*\\)'\$/\\1/p" "$COLLECT")
    if [[ -n "$quoted" ]]; then
        printf '%s' "$quoted"
        return 0
    fi
    awk -v name="$name" '
        index($0, "read -r " name " << ") == 1 { take = 1; next }
        take { print; exit }
    ' "$COLLECT"
}

patterns_present_in() {
    local file=$1 cred=$2 home=$3
    grep -F -q -- "$cred" "$file" && grep -F -q -- "$home" "$file"
}

fallback_scan_block() {
    awk '
        /^The credential and home-path scan over the added lines:/ { want = 1 }
        want && /^```bash$/ { fence = 1; next }
        fence && /^```$/ { exit }
        fence { print }
    ' "$1"
}

# The manual fallback's blocks run as written in bash and in zsh, the default
# macOS shell. A scenario that runs a block runs it once per shell present, so
# a variable named after a zsh special parameter, such as status or path, fails
# that scenario. zsh -f skips the operator's startup files.
fallback_shells() {
    printf 'bash\n'
    if command -v zsh >/dev/null 2>&1; then
        printf 'zsh\n'
    else
        log "    [zsh is not on PATH; the fallback blocks ran under bash only]"
    fi
}

run_fallback_block() {
    local fb_shell=$1 block=$2
    case "$fb_shell" in
        zsh) zsh -f -c "$block" ;;
        *) bash -c "$block" ;;
    esac
}

labeled_scan_hits() {
    local file=$1 section=$2 label=$3 body
    body=$(scan_section "$file" "$section")
    printf '%s\n' "$body" | awk -v label="$label" '
        /^  none$/ { next }
        /^  / { sub(/^  /, label " "); print }
    '
}

s29_secret_scan_patterns_match_manual_fallback() {
    local ok=true cred home fallback copy n_cred n_home passage anchor
    fallback="$SKILL_DIR/references/manual_fallback.md"
    cred=$(assigned_pattern CREDENTIAL_PATTERN)
    home=$(assigned_pattern HOME_PATH_PATTERN)
    [[ -n "$cred" && -n "$home" ]] || {
        log "    [pattern assignment missing]"
        return 1
    }
    patterns_present_in "$COLLECT" "$cred" "$home" || {
        log "    [patterns missing from the collector]"
        ok=false
    }
    patterns_present_in "$fallback" "$cred" "$home" || {
        log "    [patterns missing from the manual fallback]"
        ok=false
    }
    n_cred=$(grep -F -c -- "$cred" "$COLLECT")
    n_home=$(grep -F -c -- "$home" "$COLLECT")
    assert_eq "credential pattern appears once" "$n_cred" "1" || ok=false
    assert_eq "home-path pattern appears once" "$n_home" "1" || ok=false
    grep -q 'diff_with_header_window added' "$COLLECT" || {
        log "    [collect_secret_scan does not call the header helper]"
        ok=false
    }
    grep -q 'diff_with_header_window counts' "$COLLECT" || {
        log "    [collect_size_profile does not call the header helper]"
        ok=false
    }
    if grep -F -q -- "grep -v '^+++'" "$COLLECT"; then
        log "    [collector still filters with grep -v '^+++']"
        ok=false
    fi
    if grep -F -q -- "grep -v '^\+\+\+'" "$fallback"; then
        log "    [manual fallback still filters with grep -v '^+++']"
        ok=false
    fi
    if grep -F -q -- 'AKIA[0-9A-Z]{16}|-----BEGIN' "$fallback"; then
        log "    [manual fallback still has the short alternation]"
        ok=false
    fi
    passage=$(awk '
        /^The credential and home-path scan over the added lines:/ { on = 1 }
        on { print }
        on && /^The diff size and the binary and generated share:/ { exit }
    ' "$fallback")
    for anchor in 'diff --git' '+++' '@@'; do
        if [[ "$passage" != *"$anchor"* ]]; then
            log "    [scan passage missing anchor: $anchor]"
            ok=false
        fi
    done

    mkdir -p "$SCRATCH/s29"
    copy="$SCRATCH/s29/no-credential.md"
    grep -F -v -- "$cred" "$fallback" > "$copy"
    if patterns_present_in "$copy" "$cred" "$home"; then
        log "    [fallback check passed after the credential pattern was removed]"
        ok=false
    fi
    copy="$SCRATCH/s29/no-home.md"
    grep -F -v -- "$home" "$fallback" > "$copy"
    if patterns_present_in "$copy" "$cred" "$home"; then
        log "    [fallback check passed after the home-path pattern was removed]"
        ok=false
    fi
    $ok
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
scenario s14 "forge layer pages threads and their comments, keeps resolved/outdated" s14_forge_layer_pages_threads_and_counts_them
scenario s15 "flags: help, missing, unknown, and outside a repo"      s15_usage_and_argument_handling
scenario s16 "heading range is inclusive of both named headings"      s16_inclusive_heading_range
scenario s17 "a single heading runs to the end of the file"           s17_range_to_end_of_file
scenario s18 "range errors and the heading listing"                   s18_range_errors_and_listing
scenario s19 "the same heading twice is that section alone"           s19_single_heading_range_is_that_section_alone
scenario s20 "head_sync reports the upstream relationship"            s20_head_sync_reports_the_upstream_relationship
scenario s21 "delta rereview fixture and tag grader fail branches" s21_delta_rereview_tag_grader
scenario s22 "unreadable path records unread remainder and keeps and scans readable diffs" \
    s22_unreadable_path_records_unread_remainder
scenario s23 "push_approval logs the push, scopes TMPDIR, and grades order fail branches" \
    s23_push_approval_order_proofs
scenario s24 "size profile line counts match numstat and keep ---/+++ content lines" \
    s24_size_profile_line_counts_match_numstat
scenario s25 "secret scan locates every keep-set and added shape" \
    s25_secret_scan_locates_every_shape
scenario s26 "secret scan locates staged, index-only, and untracked shapes" \
    s26_secret_scan_locates_uncommitted_shapes
scenario s27 "secret scan reads a conflicted path against HEAD" \
    s27_secret_scan_reads_conflicted_path_against_head
scenario s28 "secret scan writes none when nothing matches" \
    s28_secret_scan_writes_none_when_nothing_matches
scenario s29 "secret-scan patterns match the manual fallback" \
    s29_secret_scan_patterns_match_manual_fallback
scenario s30 "size profile reads conflicted sections and lists binaries by their paths" \
    s30_size_profile_reads_conflicted_sections
scenario s31 "size profile lists renamed binary and generated files by their new paths" \
    s31_size_profile_lists_renames_by_new_path
scenario form_discrimination "form checks distinguish prose from field blocks" form_discrimination

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
