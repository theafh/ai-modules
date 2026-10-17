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
# Pin the bash 3.2 floor the way tests/deployment/script_tests pins DEPLOY_BASH:
# scenarios that prove floor behaviour invoke both scripts through this path
# rather than through the shebang's PATH-resolved bash.
PREPARE_BASH="/bin/bash"
PRE_FIX_TRAP_FIXTURE="$SCRIPT_DIR/prepare_commit_context_pre_fix_trap.sh"
# The never-set name p14 and p15 reference to force a set -u abort in an injected copy.
INJECTED_UNBOUND_NAME="__git_commit_inject_unbound__"
# The prepare script's final statement, which p15 pins in place: under bash 3.2
# only a completion flag set as the last statement turns a late set -u abort
# into a non-zero exit.
COMPLETION_FLAG_ASSIGNMENT="_prepare_completed=1"

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

# unborn_repo <id> -> echoes the repo path. Same local identity as
# fresh_repo, one staged file, and no commits, so HEAD does not exist.
unborn_repo() {
    local id=$1
    local repo="$SCRATCH/$id/repo"
    rm -rf "${SCRATCH:?}/${id:?}"
    mkdir -p "$repo"
    (
        cd "$repo"
        git init --quiet --initial-branch=main
        git config user.email "harness@example.com"
        git config user.name "Harness"
        printf 'root\n' > root.txt
        git add root.txt
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

# run_prepare_bash <repo> [args...] -> same as run_prepare, but through PREPARE_BASH.
run_prepare_bash() {
    local repo=$1
    shift
    local out rc
    out=$(cd "$repo" && "$PREPARE_BASH" "$PREPARE" "$@" 2>/dev/null) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# run_commit_bash <repo> <message> [context_file] -> same as run_commit, through PREPARE_BASH.
run_commit_bash() {
    local repo=$1
    local message=$2
    local ctx=${3:-}
    local out rc
    if [[ -n "$ctx" ]]; then
        out=$(cd "$repo" && printf '%s' "$message" | "$PREPARE_BASH" "$COMMIT" "$ctx" 2>/dev/null) && rc=0 || rc=$?
    else
        out=$(cd "$repo" && printf '%s' "$message" | "$PREPARE_BASH" "$COMMIT" 2>/dev/null) && rc=0 || rc=$?
    fi
    printf '%s|%s' "$rc" "$out"
}

# log_bash_version <scenario_id> — first line of /bin/bash --version into the run log.
log_bash_version() {
    local id=$1
    local ver
    ver=$("$PREPARE_BASH" --version 2>/dev/null | head -n 1)
    log "  [$id] $PREPARE_BASH --version: $ver"
}

# inject_unbound_after_trap <src> <dst> — copy src and insert one reference to
# INJECTED_UNBOUND_NAME on the line after the first line that starts with an
# EXIT trap command, so set -u aborts the copy while that trap is live. The
# line-start anchor skips comments that quote the trap, such as the pre-fix
# fixture's header, which would otherwise take the reference ahead of set -u.
inject_unbound_after_trap() {
    local src=$1 dst=$2
    awk -v name="$INJECTED_UNBOUND_NAME" '
        { print }
        /^trap .*EXIT/ && !done {
            print ": \"${" name "}\""
            done = 1
        }
    ' "$src" >"$dst"
}

# check_injected_after_trap <label> <copy> — read an injected copy without
# running it. The copy must hold exactly one EXIT trap command (a line whose
# first word is trap and whose last word is EXIT, so a comment quoting the trap
# never counts) and exactly one injected reference, and that reference must sit
# on the line directly after the trap command.
check_injected_after_trap() {
    local label=$1 copy=$2
    local trap_re='^[[:space:]]*trap[[:space:]].*[[:space:]]EXIT[[:space:]]*$'
    local trap_count ref_count ref_nr prev
    trap_count=$(grep -c -E "$trap_re" "$copy")
    ref_count=$(grep -c -F "$INJECTED_UNBOUND_NAME" "$copy")
    if [[ "$trap_count" != 1 || "$ref_count" != 1 ]]; then
        log "    [$label: expected one EXIT trap command and one injected reference, found $trap_count and $ref_count]"
        return 1
    fi
    ref_nr=$(grep -n -F "$INJECTED_UNBOUND_NAME" "$copy" | cut -d: -f1)
    prev=$(sed -n "$((ref_nr - 1))p" "$copy")
    if printf '%s\n' "$prev" | grep -q -E "$trap_re"; then
        return 0
    fi
    log "    [$label: injected reference on line $ref_nr does not follow the EXIT trap command]"
    log "      preceding line: $(printf '%q' "$prev")"
    return 1
}

# inject_unbound_before_final_statement <src> <dst> — copy src and insert one
# reference to INJECTED_UNBOUND_NAME directly before its final statement, the
# last line that is neither blank nor a comment. The anchor is that position
# rather than the completion flag's text: when the flag moves earlier or a
# statement follows it, the reference lands after the flag, where bash 3.2
# masks the abort as exit 0 and the scenario fails.
inject_unbound_before_final_statement() {
    local src=$1 dst=$2
    awk -v name="$INJECTED_UNBOUND_NAME" '
        { line[NR] = $0 }
        /[^[:space:]]/ && !/^[[:space:]]*#/ { last = NR }
        END {
            for (i = 1; i <= NR; i++) {
                if (i == last) print ": \"${" name "}\""
                print line[i]
            }
        }
    ' "$src" >"$dst"
}

# check_injected_before_flag <label> <copy> — read a late-injected copy without
# running it. The copy must hold exactly one COMPLETION_FLAG_ASSIGNMENT line and
# exactly one injected reference, and that reference must sit on the line
# directly before the assignment.
check_injected_before_flag() {
    local label=$1 copy=$2
    local flag_re="^[[:space:]]*${COMPLETION_FLAG_ASSIGNMENT}[[:space:]]*\$"
    local flag_count ref_count ref_nr next
    flag_count=$(grep -c -E "$flag_re" "$copy")
    ref_count=$(grep -c -F "$INJECTED_UNBOUND_NAME" "$copy")
    if [[ "$flag_count" != 1 || "$ref_count" != 1 ]]; then
        log "    [$label: expected one $COMPLETION_FLAG_ASSIGNMENT line and one injected reference, found $flag_count and $ref_count]"
        return 1
    fi
    ref_nr=$(grep -n -F "$INJECTED_UNBOUND_NAME" "$copy" | cut -d: -f1)
    next=$(sed -n "$((ref_nr + 1))p" "$copy")
    if printf '%s\n' "$next" | grep -q -E "$flag_re"; then
        return 0
    fi
    log "    [$label: injected reference on line $ref_nr is not directly before $COMPLETION_FLAG_ASSIGNMENT]"
    log "      following line: $(printf '%q' "$next")"
    return 1
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
# commit_with_message.sh — message-structure backstop scenario
###############################################################################

# Git reads line 1 as the subject and needs line 2 blank for the rest to parse
# as the body. The script refuses a body-bearing message that skips that blank
# line with exit 4 — a dedicated code so the refusal reads apart from the drift
# refusal (3) and from a generic failure. This scenario covers both sides of the
# check in one place: the refuse path and the two shapes that must still pass.
cx_message_structure_backstop() {
    local repo; repo=$(fresh_repo cx) || return 1
    local ok=true

    # --- refuse path: non-blank line 2 -------------------------------------
    printf 'reviewed change\n' > "$repo/seed.txt"
    local ctx; ctx=$(mktemp "${TMPDIR:-/tmp}/git_commit_context.XXXXXX")
    write_ctx "$ctx" " M seed.txt"
    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local staged_before; staged_before=$(cd "$repo" && git diff --cached --name-only)
    local rc out
    out=$(cd "$repo" && printf '%s' $'summary line\nseed.txt -> reviewed change\n' \
        | "$COMMIT" "$ctx" 2>&1) && rc=0 || rc=$?
    assert_eq "run-on message exits with structure-refusal 4" "$rc" "4" || ok=false
    assert_contains "stderr names the structure failure" "$out" "line 2 must be blank" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    assert_eq "HEAD unchanged (no commit created)" "$head_after" "$head_before" || ok=false
    local staged_after; staged_after=$(cd "$repo" && git diff --cached --name-only)
    assert_eq "index unchanged (nothing staged by the refusal)" "$staged_after" "$staged_before" || ok=false
    if [[ ! -e "$ctx" ]]; then
        log "    [context file removed on structure refusal; it must be preserved]"
        ok=false
    fi
    rm -f "$ctx"

    # --- accept path: blank line 2, body follows ---------------------------
    local rc2
    (cd "$repo" && printf '%s' $'summary line\n\nseed.txt -> reviewed change\n' \
        | "$COMMIT" >/dev/null 2>&1) && rc2=0 || rc2=$?
    assert_eq "subject + blank line + body exits 0" "$rc2" "0" || ok=false
    local subject; subject=$(cd "$repo" && git log -1 --format=%s)
    local body; body=$(cd "$repo" && git log -1 --format=%b)
    assert_eq "git parses the subject alone" "$subject" "summary line" || ok=false
    assert_contains "git parses the per-file body" "$body" "seed.txt -> reviewed change" || ok=false

    # --- accept path: one-line subject-only message ------------------------
    printf 'second change\n' > "$repo/seed.txt"
    local rc3
    (cd "$repo" && printf '%s' $'seed.txt -> second change\n' \
        | "$COMMIT" >/dev/null 2>&1) && rc3=0 || rc3=$?
    assert_eq "one-line subject-only message exits 0" "$rc3" "0" || ok=false
    local subject2; subject2=$(cd "$repo" && git log -1 --format=%s)
    assert_eq "subject-only message commits as its own subject" "$subject2" "seed.txt -> second change" || ok=false

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
# /bin/bash-pinned floor scenarios (empty-array + EXIT-trap completion flag)
###############################################################################

p12_modifications_only_under_bin_bash() {
    local repo; repo=$(fresh_repo p12) || return 1
    log_bash_version p12
    # Modifications-only empties the staged numstat list after prepare stages
    # nothing new — the empty-array copy that aborted under bash 3.2.
    printf 'changed\n' > "$repo/seed.txt"
    local ret; ret=$(run_prepare_bash "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false

    local path size directive
    path=$(printf '%s\n' "$out" | sed -n '1p')
    size=$(printf '%s\n' "$out" | sed -n '2p')
    directive=$(printf '%s\n' "$out" | sed -n '3p')
    if [[ -f "$path" ]]; then :; else
        log "    [line 1 is not a path to an existing context file: $(printf '%q' "$path")]"
        ok=false
    fi
    if [[ "$size" =~ ^[0-9]+$ ]]; then :; else
        log "    [line 2 is not a bare byte-size integer: $(printf '%q' "$size")]"
        ok=false
    fi
    if [[ -n "$directive" ]]; then :; else
        log "    [line 3 (consumption directive) is empty]"
        ok=false
    fi

    local content=""
    if [[ -f "$path" ]]; then
        content=$(cat "$path")
    fi
    assert_contains "unstaged seed.txt change" "$content" \
        '<file_change mode="unstaged" path="seed.txt">' || ok=false

    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local cret; cret=$(run_commit_bash "$repo" $'seed.txt -> changed content\n' "$path")
    local crc=${cret%%|*}
    assert_eq "commit exit" "$crc" "0" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    if [[ "$head_after" == "$head_before" ]]; then
        log "    [HEAD did not advance after commit]"
        ok=false
    fi
    local head_msg; head_msg=$(cd "$repo" && git log -1 --format=%B | head -n 1)
    assert_eq "HEAD subject" "$head_msg" "seed.txt -> changed content" || ok=false
    if [[ -e "$path" ]]; then
        log "    [context file still present after successful commit: $path]"
        rm -f "$path"
        ok=false
    fi
    $ok
}

p13_new_files_only_under_bin_bash() {
    local repo; repo=$(fresh_repo p13) || return 1
    log_bash_version p13
    # New-files-only empties the unstaged numstat list — the other empty copy.
    printf 'fresh\n' > "$repo/added.txt"
    local ret; ret=$(run_prepare_bash "$repo")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit" "$rc" "0" || ok=false

    local path size directive
    path=$(printf '%s\n' "$out" | sed -n '1p')
    size=$(printf '%s\n' "$out" | sed -n '2p')
    directive=$(printf '%s\n' "$out" | sed -n '3p')
    if [[ -f "$path" ]]; then :; else
        log "    [line 1 is not a path to an existing context file: $(printf '%q' "$path")]"
        ok=false
    fi
    if [[ "$size" =~ ^[0-9]+$ ]]; then :; else
        log "    [line 2 is not a bare byte-size integer: $(printf '%q' "$size")]"
        ok=false
    fi
    if [[ -n "$directive" ]]; then :; else
        log "    [line 3 (consumption directive) is empty]"
        ok=false
    fi

    local content=""
    if [[ -f "$path" ]]; then
        content=$(cat "$path")
    fi
    # <staged_new_files> block lists the new file.
    local new_block
    new_block=$(printf '%s\n' "$content" | sed -n '/<staged_new_files>/,/<\/staged_new_files>/p')
    assert_contains "added.txt in staged_new_files" "$new_block" "added.txt" || ok=false

    local head_before; head_before=$(cd "$repo" && git rev-parse HEAD)
    local cret; cret=$(run_commit_bash "$repo" $'added.txt -> new file\n' "$path")
    local crc=${cret%%|*}
    assert_eq "commit exit" "$crc" "0" || ok=false
    local head_after; head_after=$(cd "$repo" && git rev-parse HEAD)
    if [[ "$head_after" == "$head_before" ]]; then
        log "    [HEAD did not advance after commit]"
        ok=false
    fi
    local committed; committed=$(cd "$repo" && git show --name-only --format= HEAD)
    assert_contains "added.txt in HEAD" "$committed" "added.txt" || ok=false
    if [[ -e "$path" ]]; then
        log "    [context file still present after successful commit: $path]"
        rm -f "$path"
        ok=false
    fi
    $ok
}

p14_injected_abort_under_bin_bash() {
    local repo; repo=$(fresh_repo p14) || return 1
    log_bash_version p14
    local ok=true
    local scratch="$SCRATCH/p14"
    mkdir -p "$scratch"

    # Injected fixed prepare script: must exit non-zero with empty stdout, and
    # its stderr must name the injected reference, so the abort is the injected one.
    local fixed_copy="$scratch/prepare_injected.sh"
    local fixed_err="$scratch/prepare_injected.stderr"
    inject_unbound_after_trap "$PREPARE" "$fixed_copy"
    check_injected_after_trap "fixed copy" "$fixed_copy" || ok=false
    local fixed_out fixed_rc
    fixed_out=$(cd "$repo" && "$PREPARE_BASH" "$fixed_copy" 2>"$fixed_err") && fixed_rc=0 || fixed_rc=$?
    if (( fixed_rc == 0 )); then
        log "    [injected fixed prepare exited 0; expected non-zero]"
        ok=false
    fi
    if [[ -n "$fixed_out" ]]; then
        log "    [injected fixed prepare printed stdout; expected empty: $(printf '%q' "$fixed_out")]"
        ok=false
    fi
    assert_contains "injected fixed prepare stderr names the injected reference" \
        "$(cat "$fixed_err" 2>/dev/null)" "$INJECTED_UNBOUND_NAME" || ok=false

    # Injected pre-fix stub: the placement check reads the copy on every host;
    # the run stays gated, because only bash 3.2 masks the abort as exit 0.
    local pre_fix_copy="$scratch/pre_fix_injected.sh"
    local pre_fix_err="$scratch/pre_fix_injected.stderr"
    inject_unbound_after_trap "$PRE_FIX_TRAP_FIXTURE" "$pre_fix_copy"
    check_injected_after_trap "pre-fix copy" "$pre_fix_copy" || ok=false
    local bash_ver
    bash_ver=$("$PREPARE_BASH" --version 2>/dev/null | head -n 1)
    if [[ "$bash_ver" == *"version 3.2"* ]]; then
        local pre_out pre_rc
        pre_out=$(cd "$repo" && "$PREPARE_BASH" "$pre_fix_copy" 2>"$pre_fix_err") && pre_rc=0 || pre_rc=$?
        assert_eq "pre-fix injected abort exits 0 under bash 3.2" "$pre_rc" "0" || ok=false
        if [[ -n "$pre_out" ]]; then
            log "    [pre-fix injected abort printed stdout; expected empty: $(printf '%q' "$pre_out")]"
            ok=false
        fi
        assert_contains "pre-fix injected abort stderr names the injected reference" \
            "$(cat "$pre_fix_err" 2>/dev/null)" "$INJECTED_UNBOUND_NAME" || ok=false
    else
        log "  [p14] skipping pre-fix masked-status assertion (host $PREPARE_BASH is not 3.2)"
    fi

    $ok
}

p15_late_injected_abort_under_bin_bash() {
    local repo; repo=$(fresh_repo p15) || return 1
    log_bash_version p15
    local ok=true
    local scratch="$SCRATCH/p15"
    mkdir -p "$scratch"

    # Late-injected prepare script: set -u aborts after the three stdout lines,
    # with the completion flag still unset, so the copy must exit non-zero and
    # its stderr must name the injected reference. Under bash 3.2 only the flag
    # turns this abort into a non-zero exit, so a flag moved earlier or a
    # statement added after it fails here; newer bash exits non-zero either way,
    # and there the placement check alone pins the flag.
    local late_copy="$scratch/prepare_late_injected.sh"
    local late_err="$scratch/prepare_late_injected.stderr"
    inject_unbound_before_final_statement "$PREPARE" "$late_copy"
    check_injected_before_flag "late copy" "$late_copy" || ok=false
    local late_out late_rc
    late_out=$(cd "$repo" && "$PREPARE_BASH" "$late_copy" 2>"$late_err") && late_rc=0 || late_rc=$?
    if (( late_rc == 0 )); then
        log "    [late injected prepare exited 0; expected non-zero]"
        ok=false
    fi
    assert_contains "late injected prepare stderr names the injected reference" \
        "$(cat "$late_err" 2>/dev/null)" "$INJECTED_UNBOUND_NAME" || ok=false

    # The copy wrote its context file before the abort; remove it so no
    # git_commit_context.* straggler stays in TMPDIR.
    local ctx_path
    ctx_path=$(printf '%s\n' "$late_out" | sed -n '1p')
    if [[ -f "$ctx_path" && "$(basename "$ctx_path")" == git_commit_context.* ]]; then
        rm -f "$ctx_path"
    fi

    $ok
}

# Unborn branch: prepare writes the recent-commits placeholder, then the
# unchanged commit script turns the piped message into the root commit.
p16_unborn_branch_root_commit() {
    local repo; repo=$(unborn_repo p16) || return 1
    local stdout rc
    stdout=$(cd "$repo" && "$PREPARE" 2>/dev/null) && rc=0 || rc=$?
    local ok=true
    assert_eq "prepare exit" "$rc" "0" || ok=false

    local line_count
    line_count=$(printf '%s\n' "$stdout" | wc -l | tr -d '[:space:]')
    assert_eq "three stdout lines" "$line_count" "3" || ok=false

    local path size directive
    path=$(printf '%s\n' "$stdout" | sed -n '1p')
    size=$(printf '%s\n' "$stdout" | sed -n '2p')
    directive=$(printf '%s\n' "$stdout" | sed -n '3p')
    if [[ -f "$path" ]]; then :; else
        log "    [line 1 is not a path to an existing context file: $(printf '%q' "$path")]"
        ok=false
    fi
    if [[ "$size" =~ ^[0-9]+$ ]]; then
        local actual; actual=$(wc -c < "$path" | tr -d '[:space:]')
        assert_eq "size line matches context-file bytes" "$size" "$actual" || ok=false
    else
        log "    [line 2 is not a bare byte-size integer: $(printf '%q' "$size")]"
        ok=false
    fi
    assert_contains "consumption directive" "$directive" "Read this entire file" || ok=false

    local content=""
    if [[ -f "$path" ]]; then
        content=$(cat "$path")
    fi
    assert_contains "commit_context open" "$content" "<commit_context>" || ok=false
    assert_contains "commit_context close" "$content" "</commit_context>" || ok=false
    assert_contains "status block open" "$content" "<status_after_staging_new_files>" || ok=false
    assert_contains "status block close" "$content" "</status_after_staging_new_files>" || ok=false
    assert_contains "staged diffs open" "$content" "<staged_file_diffs>" || ok=false
    assert_contains "staged diffs close" "$content" "</staged_file_diffs>" || ok=false
    assert_contains "unstaged diffs open" "$content" "<unstaged_file_diffs>" || ok=false
    assert_contains "unstaged diffs close" "$content" "</unstaged_file_diffs>" || ok=false

    local recent_body
    recent_body=$(printf '%s\n' "$content" | awk '
        $0 == "<recent_commits>" { capture = 1; next }
        $0 == "</recent_commits>" { capture = 0; next }
        capture { lines = lines (lines == "" ? "" : "\n") $0 }
        END { printf "%s", lines }
    ')
    assert_eq "recent_commits body" "$recent_body" "(no commits yet)" || ok=false

    local message='root.txt -> initial file'
    local cret crc
    cret=$(run_commit "$repo" "$message" "$path")
    crc=${cret%%|*}
    assert_eq "commit exit" "$crc" "0" || ok=false
    local head_msg
    head_msg=$(cd "$repo" && git log -1 --format=%B)
    assert_eq "piped message is HEAD" "$head_msg" "$message" || ok=false
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
scenario p12 "prepare+commit: modifications-only under /bin/bash" p12_modifications_only_under_bin_bash
scenario p13 "prepare+commit: new-files-only under /bin/bash" p13_new_files_only_under_bin_bash
scenario p14 "prepare: injected abort exits non-zero under /bin/bash" p14_injected_abort_under_bin_bash
scenario p15 "prepare: late injected abort exits non-zero under /bin/bash" p15_late_injected_abort_under_bin_bash
scenario p16 "prepare+commit: unborn branch root commit"      p16_unborn_branch_root_commit

scenario c1  "commit: staged change with valid message"       c1_staged_change_with_message
scenario c2  "commit: untracked file gets staged by add -A"   c2_untracked_file_picked_up_by_add_a
scenario c3  "commit: empty stdin -> exit 1"                  c3_empty_stdin_rejected
scenario c4  "commit: whitespace-only stdin -> exit 1"        c4_whitespace_only_stdin_rejected
scenario c5  "commit: --help flag prints usage"               c5_help_flag
scenario c6  "commit: multi-line message preserved"           c6_multiline_message_preserved
scenario c7  "commit: context file cleaned up on success"     c7_context_file_cleanup_on_success
scenario c8  "commit: context file kept on commit failure"    c8_context_file_kept_on_failure
scenario cx  "commit: message structure backstop (exit 4)"     cx_message_structure_backstop
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
