#!/usr/bin/env bash
# Bundled-script unit tests for the git_commit skill.
#
# Scope: the two shell scripts shipped with the skill
# (prepare_commit_context.sh, commit_with_message.sh) — NOT the skill's
# agent-level behavior. Skill behavior is covered by tests/git_commit/evals/
# under the skill-creator convention.
#
# Each scenario stages a fresh temporary git repo under
# tests/git_commit/script_tests/scratch/<id>/repo/, manipulates its
# working tree, runs one of the bundled scripts, and asserts on stdout +
# exit code + post-run repo state.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/git_commit"
PREPARE="$SKILL_DIR/scripts/prepare_commit_context.sh"
COMMIT="$SKILL_DIR/scripts/commit_with_message.sh"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/layer1.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log()    { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }
indent() { sed 's/^/    /' | tee -a "$RESULTS" >&2; }

# fresh_repo <id> -> echoes the repo path, initialized with one
# committed file so HEAD exists.
fresh_repo() {
    local id=$1
    local repo="$SCRATCH/$id/repo"
    rm -rf "${SCRATCH:?}/${id:?}"
    mkdir -p "$repo"
    (
        cd "$repo"
        git init --quiet --initial-branch=main
        git config user.email "harness@example.com"
        git config user.name "Harness"
        printf 'seed\n' > seed.txt
        git add seed.txt
        git commit --quiet -m "seed"
    ) || return 1
    printf '%s' "$repo"
}

# run_prepare <repo> [args...] -> echoes "<exit>|<stdout>"; stderr suppressed.
# Use for tests that assert on the script's stdout (path + directive lines,
# or the --help banner).
run_prepare() {
    local repo=$1
    shift
    local out rc
    out=$(cd "$repo" && "$PREPARE" "$@" 2>/dev/null) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# run_prepare_content <repo> [args...] -> echoes "<exit>|<context_file_content>"
# Use for tests that assert on the context blob the script writes. Captures
# the context-file path from stdout (first line), reads the file's content,
# removes the file, and returns the content in the "out" field. Tests that
# previously asserted against stdout when the script printed the blob there
# call this helper now that the blob lives in a file.
run_prepare_content() {
    local repo=$1
    shift
    local stdout rc
    stdout=$(cd "$repo" && "$PREPARE" "$@" 2>/dev/null) && rc=0 || rc=$?
    if (( rc != 0 )); then
        printf '%s|' "$rc"
        return
    fi
    local ctx_path
    ctx_path=$(printf '%s\n' "$stdout" | head -n 1)
    local content=""
    if [[ -f "$ctx_path" ]]; then
        content=$(cat "$ctx_path")
        rm -f "$ctx_path"
    fi
    printf '%s|%s' "$rc" "$content"
}

# run_commit <repo> <message> [context_file] -> echoes "<exit>|<stdout>"; stderr suppressed.
# Pipes the message into commit_with_message.sh via stdin, matching the
# heredoc-based contract the skill instructs the model to use.
run_commit() {
    local repo=$1
    local message=$2
    local ctx=${3:-}
    local out rc
    if [[ -n "$ctx" ]]; then
        out=$(cd "$repo" && printf '%s' "$message" | "$COMMIT" "$ctx" 2>/dev/null) && rc=0 || rc=$?
    else
        out=$(cd "$repo" && printf '%s' "$message" | "$COMMIT" 2>/dev/null) && rc=0 || rc=$?
    fi
    printf '%s|%s' "$rc" "$out"
}

# write_ctx <path> [status_line...] -> writes a minimal, hand-built context
# file carrying a <status_after_staging_new_files> baseline block with the
# given verbatim short-status lines (e.g. " M seed.txt", "?? new.txt"). Stands
# in for the blob prepare_commit_context.sh would produce; the drift backstop
# in commit_with_message.sh reads only this block.
write_ctx() {
    local path=$1
    shift
    {
        printf '<commit_context>\n'
        printf '<status_after_staging_new_files>\n'
        local line
        for line in "$@"; do
            printf '%s\n' "$line"
        done
        printf '</status_after_staging_new_files>\n'
        printf '</commit_context>\n'
    } > "$path"
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

assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    fi
    log "    [unwanted substring present: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

# scenario <id> <description> <body>
# body is a function name. we run it; on any false return, the scenario fails.
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

###############################################################################
# prepare_commit_context.sh scenarios
###############################################################################

p1_clean_tree() {
    local repo; repo=$(fresh_repo p1) || return 1
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "commit_context open" "$out" "<commit_context>" || ok=false
    assert_contains "commit_context close" "$out" "</commit_context>" || ok=false
    assert_contains "staged file diffs section present" "$out" "<staged_file_diffs>" || ok=false
    assert_contains "unstaged file diffs section present" "$out" "<unstaged_file_diffs>" || ok=false
    assert_not_contains "no <file_change> on clean tree" "$out" "<file_change" || ok=false
    $ok
}

p2_one_untracked_text_file() {
    local repo; repo=$(fresh_repo p2) || return 1
    printf 'hello\n' > "$repo/new.txt"
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "new file in <staged_new_files>" "$out" "new.txt" || ok=false
    assert_contains "new file in <staged_file_diffs>" "$out" 'mode="staged" path="new.txt"' || ok=false
    # After prepare, the new file should be staged.
    local cached; cached=$(cd "$repo" && git diff --cached --name-only)
    assert_contains "git index has new.txt staged" "$cached" "new.txt" || ok=false
    $ok
}

p3_one_modified_tracked_file() {
    local repo; repo=$(fresh_repo p3) || return 1
    printf 'changed\n' > "$repo/seed.txt"
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "seed.txt in unstaged diffs" "$out" 'mode="unstaged" path="seed.txt"' || ok=false
    assert_not_contains "seed.txt not in staged diffs" "$out" 'mode="staged" path="seed.txt"' || ok=false
    $ok
}

p4_mixed_staged_unstaged_untracked() {
    local repo; repo=$(fresh_repo p4) || return 1
    # Pre-staged change to seed.txt
    printf 'staged change\n' > "$repo/seed.txt"
    (cd "$repo" && git add seed.txt) || return 1
    # Then an additional unstaged modification on top
    printf 'staged change\nplus more\n' > "$repo/seed.txt"
    # Plus an untracked new file
    printf 'fresh\n' > "$repo/added.txt"
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "added.txt staged after prepare" "$out" 'mode="staged" path="added.txt"' || ok=false
    assert_contains "seed.txt staged diff present" "$out" 'mode="staged" path="seed.txt"' || ok=false
    assert_contains "seed.txt unstaged diff present" "$out" 'mode="unstaged" path="seed.txt"' || ok=false
    $ok
}

p5_binary_file() {
    local repo; repo=$(fresh_repo p5) || return 1
    # 256 NUL bytes guarantee git classifies as binary (random urandom
    # output occasionally happens to be all-printable ASCII).
    head -c 256 /dev/zero > "$repo/blob.bin"
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "binary marker for blob.bin" "$out" "<binary_diff>" || ok=false
    assert_contains "blob.bin path tagged" "$out" 'path="blob.bin"' || ok=false
    $ok
}

p6_large_changeset_50_files() {
    local repo; repo=$(fresh_repo p6) || return 1
    # Pre-create and commit 50 files so each one has a tracked baseline
    # to be modified against.
    (
        cd "$repo"
        for i in $(seq -w 1 50); do
            printf 'v1\n' > "f$i.txt"
        done
        git add . && git commit --quiet -m "50 files"
        for i in $(seq -w 1 50); do
            printf 'v2\n' > "f$i.txt"
        done
    ) || return 1
    local start_ns end_ns elapsed_ms
    start_ns=$(date +%s)
    local ret; ret=$(run_prepare_content "$repo")
    end_ns=$(date +%s)
    elapsed_ms=$(( (end_ns - start_ns) * 1000 ))
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    # Spot-check first, middle, last
    assert_contains "f01.txt present" "$out" 'path="f01.txt"' || ok=false
    assert_contains "f25.txt present" "$out" 'path="f25.txt"' || ok=false
    assert_contains "f50.txt present" "$out" 'path="f50.txt"' || ok=false
    # Wall-clock bound: numstat caching keeps the script under ~5 seconds
    # for 50 files on any reasonable machine. A blowup to ~3 git
    # subprocesses per file would still fit, but if it ever climbs above
    # 5 seconds, performance has regressed.
    if (( elapsed_ms > 5000 )); then
        log "    [perf regression: 50-file run took ${elapsed_ms}ms (>5000ms ceiling)]"
        ok=false
    fi
    $ok
}

p7_path_with_special_chars() {
    local repo; repo=$(fresh_repo p7) || return 1
    # Filename with a space and a tab — both would split naively
    # without -z parsing in the diff loops.
    local weird=$'has space and\ttab.txt'
    printf 'special\n' > "$repo/$weird"
    local ret; ret=$(run_prepare_content "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    # The path must round-trip through the path attribute intact.
    assert_contains "weird path tagged in <staged_file_diffs>" "$out" "path=\"$weird\"" || ok=false
    $ok
}

p8_help_flag() {
    local repo; repo=$(fresh_repo p8) || return 1
    local ret; ret=$(run_prepare "$repo" --help)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "usage banner" "$out" "Usage:" || ok=false
    assert_contains "behavior banner" "$out" "Behavior:" || ok=false
    $ok
}

p9_unknown_flag() {
    local repo; repo=$(fresh_repo p9) || return 1
    local out rc
    out=$(cd "$repo" && "$PREPARE" --bogus 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "2" || ok=false
    assert_contains "error message names unknown arg" "$out" "unknown argument" || ok=false
    $ok
}

p10_outside_git_repo() {
    # SCRATCH lives inside the ai-modules repo, so any path under it
    # would walk up and find the host .git. Use mktemp under
    # /tmp (which on macOS is /private/tmp, outside any project tree)
    # to guarantee a truly non-git CWD.
    local outside; outside=$(mktemp -d) || return 1
    local rc
    (cd "$outside" && "$PREPARE" >/dev/null 2>&1) && rc=0 || rc=$?
    rm -rf "$outside"
    local ok=true
    if (( rc == 0 )); then
        log "    [expected non-zero exit outside a git repo, got 0]"
        ok=false
    fi
    $ok
}

p11_stdout_shape_path_size_directive() {
    local repo; repo=$(fresh_repo p11) || return 1
    # Dirty the tree so there is a real blob to size.
    printf 'changed\n' > "$repo/seed.txt"
    printf 'brand new\n' > "$repo/added.txt"
    local stdout rc
    stdout=$(cd "$repo" && "$PREPARE" 2>/dev/null) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false

    local path size directive
    path=$(printf '%s\n' "$stdout" | sed -n '1p')
    size=$(printf '%s\n' "$stdout" | sed -n '2p')
    directive=$(printf '%s\n' "$stdout" | sed -n '3p')

    # Line 1: the absolute path alone, pointing at an existing context file
    # the consumer carries forward unchanged to commit_with_message.sh.
    if [[ -f "$path" ]]; then :; else
        log "    [line 1 is not a path to an existing context file: $(printf '%q' "$path")]"
        ok=false
    fi

    # Line 2: a bare integer on its own line, equal to the blob's byte size.
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        local actual; actual=$(wc -c < "$path" | tr -d '[:space:]')
        assert_eq "size line matches context-file bytes" "$size" "$actual" || ok=false
    else
        log "    [line 2 is not a bare byte-size integer: $(printf '%q' "$size")]"
        ok=false
    fi

    # Line 3: a harness-neutral directive — no longer names the Read tool as
    # the sole mechanism, still forbids git re-derivation.
    assert_not_contains "directive drops Read-tool-only wording" "$directive" "Read this entire file with the Read tool" || ok=false
    assert_contains "directive offers a shell reader" "$directive" "shell slices" || ok=false
    assert_contains "directive still forbids git re-derivation" "$directive" "Do NOT re-run git diff" || ok=false

    rm -f "$path"
    $ok
}

###############################################################################
# commit_with_message.sh scenarios
###############################################################################

c1_staged_change_with_message() {
    local repo; repo=$(fresh_repo c1) || return 1
    printf 'updated\n' > "$repo/seed.txt"
    (cd "$repo" && git add seed.txt) || return 1
    local ret; ret=$(run_commit "$repo" $'seed.txt -> change body\n')
    local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    # Final status should be empty (single line == empty in --short)
    local status; status=$(cd "$repo" && git status --short)
    assert_eq "post-commit status empty" "$status" "" || ok=false
    # HEAD message matches what we wrote
    local head_msg; head_msg=$(cd "$repo" && git log -1 --format=%B | head -n 1)
    assert_eq "HEAD subject" "$head_msg" "seed.txt -> change body" || ok=false
    $ok
}

c2_untracked_file_picked_up_by_add_a() {
    local repo; repo=$(fresh_repo c2) || return 1
    printf 'fresh\n' > "$repo/added.txt"
    local ret; ret=$(run_commit "$repo" $'added.txt -> new file\n')
    local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD | sort)
    assert_contains "added.txt landed in HEAD" "$committed" "added.txt" || ok=false
    $ok
}

c3_empty_stdin_rejected() {
    local repo; repo=$(fresh_repo c3) || return 1
    local rc out
    out=$(cd "$repo" && : | "$COMMIT" 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_contains "error names empty message" "$out" "empty" || ok=false
    $ok
}

c4_whitespace_only_stdin_rejected() {
    local repo; repo=$(fresh_repo c4) || return 1
    local rc out
    out=$(cd "$repo" && printf '   \n\t\n' | "$COMMIT" 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "1" || ok=false
    assert_contains "error names empty message" "$out" "empty" || ok=false
    $ok
}

c5_help_flag() {
    local rc out
    out=$("$COMMIT" --help 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    assert_contains "usage banner" "$out" "Usage:" || ok=false
    $ok
}

c6_multiline_message_preserved() {
    local repo; repo=$(fresh_repo c6) || return 1
    printf 'updated\n' > "$repo/seed.txt"
    (cd "$repo" && git add seed.txt) || return 1
    local ret; ret=$(run_commit "$repo" $'summary line\n\nbody line one\nbody line two\n')
    local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    local head_body; head_body=$(cd "$repo" && git log -1 --format=%B)
    assert_contains "subject preserved" "$head_body" "summary line" || ok=false
    assert_contains "body line 1 preserved" "$head_body" "body line one" || ok=false
    assert_contains "body line 2 preserved" "$head_body" "body line two" || ok=false
    $ok
}

c7_context_file_cleanup_on_success() {
    local repo; repo=$(fresh_repo c7) || return 1
    printf 'updated\n' > "$repo/seed.txt"
    (cd "$repo" && git add seed.txt) || return 1
    # Simulate a context file produced by prepare_commit_context.sh.
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    printf 'stale context\n' > "$ctx"
    local ret; ret=$(run_commit "$repo" $'seed.txt -> body\n' "$ctx")
    local rc=${ret%%|*}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false
    if [[ -e "$ctx" ]]; then
        log "    [context file still present after successful commit: $ctx]"
        rm -f "$ctx"
        ok=false
    fi
    $ok
}

c8_context_file_kept_on_failure() {
    local repo; repo=$(fresh_repo c8) || return 1
    # No staged changes and no untracked files -> git commit fails with
    # "nothing to commit". Context file must survive for the next attempt.
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    printf 'preserved context\n' > "$ctx"
    local rc out
    out=$(cd "$repo" && printf 'subject\n' | "$COMMIT" "$ctx" 2>&1) && rc=0 || rc=$?
    local ok=true
    if (( rc == 0 )); then
        log "    [expected non-zero exit when nothing to commit, got 0]"
        ok=false
    fi
    if [[ ! -e "$ctx" ]]; then
        log "    [context file was removed despite commit failure]"
        ok=false
    fi
    rm -f "$ctx"
    $ok
}

###############################################################################
# commit_with_message.sh — foreign-drift backstop scenarios
###############################################################################

c9_foreign_drift_blocks() {
    local repo; repo=$(fresh_repo c9) || return 1
    # Reviewed change: seed.txt modified. Baseline records only that path.
    printf 'reviewed change\n' > "$repo/seed.txt"
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    write_ctx "$ctx" " M seed.txt"
    # Foreign drift: a path appears that was outside the reviewed baseline.
    printf 'from another session\n' > "$repo/foreign.txt"
    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local rc out
    out=$(cd "$repo" && printf '%s' $'seed.txt -> reviewed change\n' | "$COMMIT" "$ctx" 2>&1) && rc=0 || rc=$?
    local ok=true
    # Exit 3 is the reserved drift-refusal code — distinct from the 1
    # (empty message, c3/c4) and 2 (TTY refusal) the script already returns,
    # so an intentional refusal reads apart from a generic failure.
    assert_eq "exit is drift-refusal 3" "$rc" "3" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    assert_eq "HEAD unchanged (no commit created)" "$head_after" "$head_before" || ok=false
    assert_contains "offending path printed" "$out" "foreign.txt" || ok=false
    if [[ ! -e "$ctx" ]]; then
        log "    [context file removed on drift refusal; it must be preserved]"
        ok=false
    fi
    rm -f "$ctx"
    $ok
}

c10_accept_drift_override_commits() {
    local repo; repo=$(fresh_repo c10) || return 1
    printf 'reviewed change\n' > "$repo/seed.txt"
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    write_ctx "$ctx" " M seed.txt"
    printf 'from another session\n' > "$repo/foreign.txt"
    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local rc
    (cd "$repo" && printf '%s' $'commit all\n\nseed.txt -> reviewed change\nforeign.txt -> new file\n' \
        | "$COMMIT" "$ctx" --accept-drift >/dev/null 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit 0 with --accept-drift override" "$rc" "0" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    if [[ "$head_after" == "$head_before" ]]; then
        log "    [no new commit created under --accept-drift]"
        ok=false
    fi
    # Every path lands in the commit, including the previously drifted one.
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD)
    assert_contains "seed.txt in commit" "$committed" "seed.txt" || ok=false
    assert_contains "foreign.txt in commit" "$committed" "foreign.txt" || ok=false
    if [[ -e "$ctx" ]]; then
        log "    [context file still present after override commit; must be removed]"
        rm -f "$ctx"
        ok=false
    fi
    $ok
}

c11_no_drift_passthrough_preserved() {
    local repo; repo=$(fresh_repo c11) || return 1
    # Current status path set matches the baseline exactly — no drift.
    printf 'reviewed change\n' > "$repo/seed.txt"
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    write_ctx "$ctx" " M seed.txt"
    local rc
    (cd "$repo" && printf '%s' $'seed.txt -> reviewed change\n' \
        | "$COMMIT" "$ctx" >/dev/null 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit 0, no override needed" "$rc" "0" || ok=false
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD)
    assert_contains "seed.txt committed" "$committed" "seed.txt" || ok=false
    if [[ -e "$ctx" ]]; then
        log "    [context file not cleaned up on a clean commit]"
        rm -f "$ctx"
        ok=false
    fi
    $ok
}

c12_same_path_reedit_passthrough() {
    local repo; repo=$(fresh_repo c12) || return 1
    # Baseline lists a dirty path X (seed.txt), staged-modified -> "M  seed.txt".
    printf 'first pass\n' > "$repo/seed.txt"
    (cd "$repo" && git add seed.txt) || return 1
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    write_ctx "$ctx" "M  seed.txt"
    # Re-edit the SAME path after capture so its short-status line shifts
    # (M  -> MM) while no path outside the baseline appears. A status-line
    # equality check would read the shifted line as a new path and block;
    # the path-set comparison commits it.
    printf 'first pass\nsecond pass\n' > "$repo/seed.txt"
    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local rc
    (cd "$repo" && printf '%s' $'seed.txt -> two-pass edit\n' \
        | "$COMMIT" "$ctx" >/dev/null 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "same-path re-edit commits (exit 0, not blocked)" "$rc" "0" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    if [[ "$head_after" == "$head_before" ]]; then
        log "    [HEAD did not advance; same-path re-edit was wrongly blocked]"
        ok=false
    fi
    # The re-edited working-tree content is what landed.
    local committed_content; committed_content=$(cd "$repo" && git show HEAD:seed.txt)
    assert_contains "re-edited content landed in commit" "$committed_content" "second pass" || ok=false
    if [[ -e "$ctx" ]]; then
        log "    [context file not cleaned up]"
        rm -f "$ctx"
        ok=false
    fi
    $ok
}

c13_missing_baseline_no_context_file() {
    local repo; repo=$(fresh_repo c13) || return 1
    # No context file at all -> no baseline -> commit-all, even though a
    # never-reviewed path (added.txt) is present. No false drift block.
    printf 'change\n' > "$repo/seed.txt"
    printf 'brand new\n' > "$repo/added.txt"
    local rc
    (cd "$repo" && printf '%s' $'commit all\n\nseed.txt -> change\nadded.txt -> new\n' \
        | "$COMMIT" >/dev/null 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit 0 (commit-all, no baseline)" "$rc" "0" || ok=false
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD)
    assert_contains "seed.txt committed" "$committed" "seed.txt" || ok=false
    assert_contains "added.txt committed" "$committed" "added.txt" || ok=false
    $ok
}

c14_missing_baseline_context_without_block() {
    local repo; repo=$(fresh_repo c14) || return 1
    # Context file present but carrying no <status_after_staging_new_files>
    # block -> no baseline -> commit-all, no false drift block.
    printf 'change\n' > "$repo/seed.txt"
    printf 'brand new\n' > "$repo/added.txt"
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    printf '<commit_context>\n<recent_commits>\ndeadbee seed\n</recent_commits>\n</commit_context>\n' > "$ctx"
    local rc
    (cd "$repo" && printf '%s' $'commit all\n\nseed.txt -> change\nadded.txt -> new\n' \
        | "$COMMIT" "$ctx" >/dev/null 2>&1) && rc=0 || rc=$?
    local ok=true
    assert_eq "exit 0 (commit-all, block absent)" "$rc" "0" || ok=false
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD)
    assert_contains "seed.txt committed" "$committed" "seed.txt" || ok=false
    assert_contains "added.txt committed" "$committed" "added.txt" || ok=false
    if [[ -e "$ctx" ]]; then
        log "    [context file not cleaned up on success]"
        rm -f "$ctx"
        ok=false
    fi
    $ok
}

###############################################################################
# Run scenarios
###############################################################################

scenario p1  "prepare: clean tree"                            p1_clean_tree
scenario p2  "prepare: one untracked text file"               p2_one_untracked_text_file
scenario p3  "prepare: one modified tracked file"             p3_one_modified_tracked_file
scenario p4  "prepare: mixed staged + unstaged + untracked"   p4_mixed_staged_unstaged_untracked
scenario p5  "prepare: binary file"                           p5_binary_file
scenario p6  "prepare: 50 modified files (perf bound)"        p6_large_changeset_50_files
scenario p7  "prepare: path with space and tab"               p7_path_with_special_chars
scenario p8  "prepare: --help flag"                           p8_help_flag
scenario p9  "prepare: unknown flag rejected"                 p9_unknown_flag
scenario p10 "prepare: run outside a git repo fails"          p10_outside_git_repo
scenario p11 "prepare: stdout path + size + neutral directive" p11_stdout_shape_path_size_directive

scenario c1  "commit: staged change with valid message"       c1_staged_change_with_message
scenario c2  "commit: untracked file gets staged by add -A"   c2_untracked_file_picked_up_by_add_a
scenario c3  "commit: empty stdin -> exit 1"                  c3_empty_stdin_rejected
scenario c4  "commit: whitespace-only stdin -> exit 1"        c4_whitespace_only_stdin_rejected
scenario c5  "commit: --help flag prints usage"               c5_help_flag
scenario c6  "commit: multi-line message preserved"           c6_multiline_message_preserved
scenario c7  "commit: context file cleaned up on success"     c7_context_file_cleanup_on_success
scenario c8  "commit: context file kept on commit failure"    c8_context_file_kept_on_failure
scenario c9  "commit: foreign drift blocks (exit 3)"          c9_foreign_drift_blocks
scenario c10 "commit: --accept-drift override commits"        c10_accept_drift_override_commits
scenario c11 "commit: no-drift pass-through preserved"        c11_no_drift_passthrough_preserved
scenario c12 "commit: same-path re-edit passes through"       c12_same_path_reedit_passthrough
scenario c13 "commit: missing baseline (no ctx) -> commit-all" c13_missing_baseline_no_context_file
scenario c14 "commit: missing baseline (no block) -> commit-all" c14_missing_baseline_context_without_block

###############################################################################
# Summary
###############################################################################

log ""
log "================================================================"
log "  $((PASS+FAIL)) scenarios — $PASS pass, $FAIL fail"
if (( FAIL > 0 )); then
    log "  failed: ${FAILED_IDS[*]}"
fi
log "================================================================"

if (( FAIL > 0 )); then
    exit 1
fi
exit 0
