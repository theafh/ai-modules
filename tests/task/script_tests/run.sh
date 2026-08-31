#!/usr/bin/env bash
# Bundled-script unit tests for the task skill family.
#
# Scope: the shell + python programs shipped with the base `task` skill
# (discover_tasks.sh, init_tasks.sh, lint.py) — NOT the skills'
# agent-level behavior. Skill prose behavior (base `task` and the seven
# siblings) is covered by tests/task/evals/ under the skill-creator
# convention; family routing by tests/trigger_evals/task.json.
#
# The seven sibling skills (task_create/_check/_select/_implement/_audit/
# _finish/_fix) ship no scripts of their own — they lean on these three. So
# this file is the full mechanical surface for the whole family.
#
# Coverage groups:
#   d* discover_tasks.sh — git-toplevel resolution, marker walk, exit
#      codes (0 when tasks/ exists, 1 when not, 2 on bad arg), --help.
#   i* init_tasks.sh     — scaffold tasks/+archive/, idempotency,
#      refusal on a non-directory target, arg/exit handling, --help.
#   l* lint.py body link resolution (check_local_links): a `.md` link
#      resolves against the task's own directory and, as a fallback,
#      against the project root (tasks.parent); a target missing under
#      both blocks.
#   am* the base skill's <archive> step 3 move instruction, executed as
#      the shell sequence it names: one `git ls-files --error-unmatch`
#      probe, `git mv` on a tracked file, plain `mv` on a non-zero probe.
#      Mechanical command semantics rather than model behavior; the prose
#      an agent reads is graded in tests/task/evals/.
#   n*/f*/loc*/prov*/col*/md*/sc*/sz*/c* lint.py's remaining checks: filename
#      naming, frontmatter completeness/validity, provenance,
#      status↔location, archive migration, cross open+archive name collisions, standard-markdown
#      (footnotes/wikilinks), scope resolution, page size, clean tree.
#
# Each scenario stages a throwaway tasks/ tree under
# tests/task/script_tests/scratch/<id>/. The d*/i* scenarios stage
# OUTSIDE the repo (mktemp) so the surrounding ai-modules git tree does
# not shadow the discovery logic under test.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_DIR="$REPO_ROOT/plugins/ai_dev/skills/task"
LINT="$SKILL_DIR/scripts/lint.py"
DISCOVER="$SKILL_DIR/scripts/discover_tasks.sh"
INIT="$SKILL_DIR/scripts/init_tasks.sh"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

PASS=0
FAIL=0
SKIP=0
FAILED_IDS=()

# External (out-of-repo) temp dirs created for the discover/init
# scenarios. Cleaned on exit so the surrounding git tree never matters.
EXT_TMPS=()
ext_tmp() {
    local d
    d=$(mktemp -d "${TMPDIR:-/tmp}/tasks_st.XXXXXX")
    EXT_TMPS+=("$d")
    printf '%s' "$d"
}
cleanup_ext() {
    local d
    for d in "${EXT_TMPS[@]:-}"; do
        [[ -n "$d" && -d "$d" ]] && rm -rf "$d"
    done
}
trap cleanup_ext EXIT

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log()  { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

# fresh_tasks <id> -> echoes a scaffolded tasks/ path with an archive/.
fresh_tasks() {
    local id=$1
    local tasks="$SCRATCH/$id/tasks"
    rm -rf "${SCRATCH:?}/$id"
    mkdir -p "$tasks/archive"
    printf '%s' "$tasks"
}

# write_task <tasks> <filename> <created> -> writes a valid task file
# whose `created` frontmatter is the supplied value. `updated` is set
# to the same value; status open; scope a quoted label so the scope
# check stays out of the way.
write_task() {
    local tasks=$1 filename=$2 created=$3
    cat > "$tasks/$filename" <<EOF
---
description: valid task harness fixture
scope: "test"
created: $created
updated: $created
status: open
reported-by: Test User
---

# Valid task fixture

Body content so the H1 check stays happy.
EOF
}

# write_linking_task <tasks> <filename> <link_target> -> writes a valid
# task whose body holds a single markdown link to <link_target>.
# created/updated are stamped to now so link resolution is the only
# behaviour under test.
write_linking_task() {
    local tasks=$1 filename=$2 link_target=$3 now
    now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/$filename" <<EOF
---
description: link-resolution harness fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Link-resolution fixture

See [the target]($link_target) for details.
EOF
}

# run_lint <tasks> [args...] -> echoes "<exit>|<combined output>".
run_lint() {
    local tasks=$1 out rc
    shift || true
    out=$(python3 "$LINT" "$tasks" "$@" 2>&1) && rc=0 || rc=$?
    printf '%s|%s' "$rc" "$out"
}

# run_discover_in <dir> [args...] -> echoes "<exit>|<combined output>",
# running discover_tasks.sh with CWD set to <dir> so resolution reflects
# that directory's project context.
run_discover_in() {
    local dir=$1; shift
    local out rc
    out=$(cd "$dir" && "$DISCOVER" "$@" 2>&1); rc=$?
    printf '%s|%s' "$rc" "$out"
}

# run_init <args...> -> echoes "<exit>|<combined output>".
run_init() {
    local out rc
    out=$("$INIT" "$@" 2>&1); rc=$?
    printf '%s|%s' "$rc" "$out"
}

# in_git_tree <dir> -> 0 if <dir> sits inside a git working tree.
in_git_tree() {
    git -C "$1" rev-parse --show-toplevel >/dev/null 2>&1
}

git_commit_fixture() {
    local repo=$1 name=$2 message=$3
    git -C "$repo" add tasks
    git -C "$repo" -c user.name="$name" -c user.email="${name// /_}@example.test" \
        commit -q -m "$message"
}

# archive_move <root> <live-rel> <archive-rel> -> echoes the branch taken
# ("git mv" or "mv"). Implements the base `task` skill's <archive> step 3
# move instruction verbatim: probe the live path once with
# `git ls-files --error-unmatch`, move with `git mv` on exit 0, and move
# with plain `mv` on any non-zero exit.
archive_move() {
    local root=$1 live=$2 archived=$3
    if git -C "$root" ls-files --error-unmatch "$live" >/dev/null 2>&1; then
        git -C "$root" mv "$live" "$archived" && printf 'git mv'
    else
        mv "$root/$live" "$root/$archived" && printf 'mv'
    fi
}

assert_eq() {
    local label=$1 actual=$2 expected=$3
    if [[ "$actual" == "$expected" ]]; then return 0; fi
    log "    [diff: $label]"
    log "      expected: $(printf '%q' "$expected")"
    log "      actual:   $(printf '%q' "$actual")"
    return 1
}

assert_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" == *"$needle"* ]]; then return 0; fi
    log "    [missing substring: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" != *"$needle"* ]]; then return 0; fi
    log "    [unwanted substring present: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

scenario() {
    local id=$1 desc=$2 body=$3
    log ""
    log "=== $id  $desc ==="
    "$body"
    local rc=$?
    case $rc in
        0) PASS=$((PASS+1)); log "  PASS" ;;
        2) SKIP=$((SKIP+1)); log "  SKIP" ;;
        *) FAIL=$((FAIL+1)); FAILED_IDS+=("$id"); log "  FAIL" ;;
    esac
}

###############################################################################
# Link-resolution scenarios.
###############################################################################

l1_project_root_fallback_resolves() {
    local tasks; tasks=$(fresh_tasks l1)
    # The linter's project_root is tasks.parent. Stage a "repo source
    # file" there and link to it with a project-root-relative path.
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/src"
    : > "$root/src/thing.md"
    write_linking_task "$tasks" "test_fallback.md" "src/thing.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (project-root-relative link resolves via fallback)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link for project-root-relative target" "$out" "broken-link" || ok=false
    $ok
}

l2_missing_under_both_roots_blocks() {
    local tasks; tasks=$(fresh_tasks l2)
    # Target exists under neither the task dir nor the project root.
    write_linking_task "$tasks" "test_missing.md" "src/nope.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (target missing under both roots blocks)" "$rc" "1" || ok=false
    assert_contains "broken-link finding fires" "$out" "broken-link" || ok=false
    assert_contains "message names the project-root attempt" "$out" "also tried project root" || ok=false
    $ok
}

l3_sibling_task_link_resolves() {
    local tasks; tasks=$(fresh_tasks l3)
    # A relative link to a sibling task in the same dir keeps resolving
    # against the task's own directory (the original, non-fallback path).
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_sibling.md" "$now"
    write_linking_task "$tasks" "test_linker.md" "test_sibling.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (sibling-task link resolves)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link for sibling task" "$out" "broken-link" || ok=false
    $ok
}

###############################################################################
# discover_tasks.sh scenarios — staged outside the repo.
###############################################################################

d1_git_toplevel_resolves() {
    local dir; dir=$(ext_tmp)
    git -C "$dir" init -q
    mkdir -p "$dir/tasks/archive"
    local ret; ret=$(run_discover_in "$dir")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (tasks/ exists under git toplevel)" "$rc" "0" || ok=false
    assert_contains "prints <toplevel>/tasks" "$out" "$(basename "$dir")/tasks" || ok=false
    $ok
}

d2_missing_tasks_exits_one() {
    local dir; dir=$(ext_tmp)
    git -C "$dir" init -q
    # No tasks/ created — discover still prints the path but signals 1.
    local ret; ret=$(run_discover_in "$dir")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (tasks/ does not exist yet)" "$rc" "1" || ok=false
    assert_contains "still prints the resolved tasks path" "$out" "$(basename "$dir")/tasks" || ok=false
    $ok
}

d3_marker_walk_from_subdir() {
    local dir; dir=$(ext_tmp)
    # No git here — exercise the project-marker walk. `.project-root` is
    # the closest marker, so resolution lands on $dir even if some
    # ancestor of the temp dir happens to carry another marker.
    : > "$dir/.project-root"
    mkdir -p "$dir/sub/deep"
    if in_git_tree "$dir"; then
        log "    [temp dir sits inside a git tree — marker-walk path N/A]"
        return 2
    fi
    local ret; ret=$(run_discover_in "$dir/sub/deep")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (resolved root has no tasks/ yet)" "$rc" "1" || ok=false
    assert_contains "walks up to the marker dir" "$out" "$(basename "$dir")/tasks" || ok=false
    $ok
}

d4_bad_argument_exits_two() {
    local dir; dir=$(ext_tmp)
    local ret; ret=$(run_discover_in "$dir" bogus-arg)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 2 (unknown argument)" "$rc" "2" || ok=false
    assert_contains "names the bad argument" "$out" "unknown argument" || ok=false
    $ok
}

d5_help_exits_zero() {
    local dir; dir=$(ext_tmp)
    local ret; ret=$(run_discover_in "$dir" --help)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (--help)" "$rc" "0" || ok=false
    assert_contains "help describes resolution order" "$out" "Resolution order" || ok=false
    $ok
}

###############################################################################
# init_tasks.sh scenarios — staged outside the repo.
###############################################################################

i1_scaffolds_tasks_and_archive() {
    local dir; dir=$(ext_tmp)
    local target="$dir/proj/tasks"
    local ret; ret=$(run_init "$target")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (fresh scaffold)" "$rc" "0" || ok=false
    assert_contains "reports the ready path" "$out" "tasks directory ready at" || ok=false
    [[ -d "$target" ]]         || { log "    [tasks dir not created]"; ok=false; }
    [[ -d "$target/archive" ]] || { log "    [archive/ not created]"; ok=false; }
    $ok
}

i2_idempotent_on_existing() {
    local dir; dir=$(ext_tmp)
    local target="$dir/proj/tasks"
    run_init "$target" >/dev/null
    : > "$target/keep_marker.md"   # pre-existing content must survive
    local ret; ret=$(run_init "$target")
    local rc=${ret%%|*}
    local ok=true
    assert_eq "exit 0 (idempotent re-init)" "$rc" "0" || ok=false
    [[ -f "$target/keep_marker.md" ]] || { log "    [re-init clobbered existing content]"; ok=false; }
    $ok
}

i3_refuses_non_directory_target() {
    local dir; dir=$(ext_tmp)
    local target="$dir/afile"
    : > "$target"   # a regular file sits where the dir would go
    local ret; ret=$(run_init "$target")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (refuses to clobber a file)" "$rc" "1" || ok=false
    assert_contains "explains the refusal" "$out" "refusing to init" || ok=false
    [[ -f "$target" ]] || { log "    [the pre-existing file was destroyed]"; ok=false; }
    $ok
}

i4_no_argument_exits_two() {
    local ret; ret=$(run_init)
    local rc=${ret%%|*}
    assert_eq "exit 2 (missing PATH argument)" "$rc" "2"
}

i5_help_exits_zero() {
    local ret; ret=$(run_init --help)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (--help)" "$rc" "0" || ok=false
    assert_contains "help shows usage" "$out" "init_tasks.sh — create" || ok=false
    $ok
}

###############################################################################
# lint.py — filename / frontmatter / location / collision / markdown /
# scope / size / clean scenarios. created/updated are stamped to now so
# each scenario isolates one rule under test.
###############################################################################

# emit <path> <<<heredoc — write arbitrary file content from stdin.
emit() { cat > "$1"; }

n1_bad_filename_blocks() {
    local tasks; tasks=$(fresh_tasks n1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/BadName.md" <<EOF
---
description: bad filename fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Bad filename
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (filename violates <scope>_<name>.md)" "$rc" "1" || ok=false
    assert_contains "names the naming category" "$out" "naming" || ok=false
    assert_contains "explains the convention" "$out" "does not match" || ok=false
    $ok
}

f1_missing_frontmatter_blocks() {
    local tasks; tasks=$(fresh_tasks f1)
    emit "$tasks/test_nofm.md" <<EOF
# No frontmatter

Body only, no fences.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (no frontmatter)" "$rc" "1" || ok=false
    assert_contains "reports malformed frontmatter" "$out" "missing or malformed frontmatter" || ok=false
    $ok
}

f2_missing_required_field_blocks() {
    local tasks; tasks=$(fresh_tasks f2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_nostatus.md" <<EOF
---
description: missing status fixture
scope: "test"
created: $now
updated: $now
---

# Missing status
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (status field absent)" "$rc" "1" || ok=false
    assert_contains "names the missing field" "$out" "missing required field: status" || ok=false
    $ok
}

f3_invalid_status_blocks() {
    local tasks; tasks=$(fresh_tasks f3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_badstatus.md" <<EOF
---
description: invalid status fixture
scope: "test"
created: $now
updated: $now
status: wip
reported-by: Test User
---

# Invalid status
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (status not in the valid set)" "$rc" "1" || ok=false
    assert_contains "rejects the value" "$out" "invalid status" || ok=false
    $ok
}

f4_non_iso_datetime_warns() {
    local tasks; tasks=$(fresh_tasks f4)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_baddate.md" <<EOF
---
description: non-ISO datetime fixture
scope: "test"
created: May 1 2026
updated: $now
status: open
reported-by: Test User
---

# Bad datetime
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (datetime format is warn, not blocking)" "$rc" "0" || ok=false
    assert_contains "warns on the format" "$out" "ISO 8601 format" || ok=false
    $ok
}

f5_missing_h1_warns() {
    local tasks; tasks=$(fresh_tasks f5)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_noh1.md" <<EOF
---
description: missing H1 fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

Body text with no level-one heading.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (missing title is warn)" "$rc" "0" || ok=false
    assert_contains "warns on the missing title" "$out" 'no `# Title`' || ok=false
    $ok
}

loc1_archived_non_terminal_silent_by_default() {
    local tasks; tasks=$(fresh_tasks loc1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/archive/test_misplaced.md" <<EOF
---
description: legacy implemented task under archive fixture
scope: "test"
created: $now
updated: $now
status: implemented
design-extended: false
reported-by: Test User
---

# Legacy implemented task
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (default mode skips archive per-file checks)" "$rc" "0" || ok=false
    assert_not_contains "no migration finding by default" "$out" "migration" || ok=false
    $ok
}

loc2_finished_in_root_blocks() {
    local tasks; tasks=$(fresh_tasks loc2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_done.md" <<EOF
---
description: finished task left in tasks root fixture
scope: "test"
created: $now
updated: $now
status: finished
design-extended: false
reported-by: Test User
implemented-by: Test User
---

# Finished but not archived
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (finished task in tasks root)" "$rc" "1" || ok=false
    assert_contains "names the location mismatch" "$out" "status is \`finished\` but file lives under tasks/" || ok=false
    assert_contains "hints the archive move" "$out" "move to" || ok=false
    $ok
}

loc3_ready_in_root_clean() {
    local tasks; tasks=$(fresh_tasks loc3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_ready.md" <<EOF
---
description: ready task fixture
scope: "test"
created: $now
updated: $now
status: ready
reported-by: Test User
---

# Ready task
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (ready is a valid live status)" "$rc" "0" || ok=false
    assert_not_contains "ready is not invalid" "$out" "invalid status" || ok=false
    $ok
}

loc4_archived_non_terminal_migrates_in_archive_mode() {
    local tasks; tasks=$(fresh_tasks loc4)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/archive/test_legacy.md" <<EOF
---
description: legacy implemented archive fixture
scope: "test"
created: $now
updated: $now
status: implemented
design-extended: false
reported-by: Test User
implemented-by: Test User
---

# Legacy implemented archive
EOF
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (archive mode reports legacy status migration)" "$rc" "1" || ok=false
    assert_contains "migration finding fires" "$out" "migration" || ok=false
    assert_contains "names the finished migration" "$out" "migrate to \`status: finished\`" || ok=false
    assert_contains "names the no-updated-bump note" "$out" "does not bump \`updated\`" || ok=false
    assert_not_contains "no competing move-to-root hint" "$out" "move to $tasks/test_legacy.md" || ok=false
    $ok
}

prov1_missing_reported_by_blocks() {
    local tasks; tasks=$(fresh_tasks prov1)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    git -C "$root" config user.name "Configured User"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_missing-reporter.md" <<EOF
---
description: missing reporter fixture
scope: "test"
created: $now
updated: $now
status: open
---

# Missing reporter
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (reported-by is mandatory)" "$rc" "1" || ok=false
    assert_contains "names reported-by" "$out" "missing required field: reported-by" || ok=false
    assert_contains "carries the exact line to add" "$out" "\`reported-by: Configured User\`" || ok=false
    $ok
}

prov2_implemented_requires_implemented_by() {
    local tasks; tasks=$(fresh_tasks prov2)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    git -C "$root" config user.name "Implementer User"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_implemented.md" <<EOF
---
description: implemented task missing implementer fixture
scope: "test"
created: $now
updated: $now
status: implemented
design-extended: false
reported-by: Test User
---

# Missing implementer
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (implemented-by is mandatory for implemented)" "$rc" "1" || ok=false
    assert_contains "names implemented-by" "$out" "missing required field: implemented-by" || ok=false
    assert_contains "falls back to git config user.name" "$out" "\`implemented-by: Implementer User\`" || ok=false
    $ok
}

prov3_deferred_without_implemented_by_clean() {
    local tasks; tasks=$(fresh_tasks prov3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/archive/test_deferred.md" <<EOF
---
description: deferred task fixture
scope: "test"
created: $now
updated: $now
status: deferred
reported-by: Test User
---

# Deferred task
EOF
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (deferred does not require implemented-by)" "$rc" "0" || ok=false
    assert_not_contains "no implemented-by finding" "$out" "implemented-by" || ok=false
    $ok
}

prov4_reported_by_uses_first_commit_author() {
    local tasks; tasks=$(fresh_tasks prov4)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_history-reporter.md" <<EOF
---
description: tracked task missing reporter fixture
scope: "test"
created: $now
updated: $now
status: open
---

# Missing reporter from history
EOF
    git_commit_fixture "$root" "Original Reporter" "seed: task added without reporter"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (missing reported-by blocks)" "$rc" "1" || ok=false
    assert_contains "uses first-add author" "$out" "\`reported-by: Original Reporter\`" || ok=false
    assert_contains "names first-add source" "$out" "first-add commit author" || ok=false
    $ok
}

prov5_archived_finished_implemented_by_uses_rename_author() {
    local tasks; tasks=$(fresh_tasks prov5)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_done.md" <<EOF
---
description: task that will be archived without implementer
scope: "test"
created: $now
updated: $now
status: implemented
design-extended: false
reported-by: Original Reporter
implemented-by: Builder User
---

# Task to archive
EOF
    git_commit_fixture "$root" "Original Reporter" "seed: implemented task"
    git -C "$root" mv tasks/test_done.md tasks/archive/test_done.md
    perl -0pi -e 's/status: implemented\nreported-by:/status: finished\nreported-by:/; s/implemented-by: Builder User\n//' "$tasks/archive/test_done.md"
    git_commit_fixture "$root" "Archive Mover" "archive: finish task"
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (missing implemented-by blocks on finished archive)" "$rc" "1" || ok=false
    assert_contains "uses archive-move author" "$out" "\`implemented-by: Archive Mover\`" || ok=false
    assert_contains "names archive-move source" "$out" "archive-move commit author" || ok=false
    $ok
}

col1_duplicate_name_across_roots_blocks() {
    local tasks; tasks=$(fresh_tasks col1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_dup.md" <<EOF
---
description: open copy fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Duplicate (open copy)
EOF
    emit "$tasks/archive/test_dup.md" <<EOF
---
description: archived copy fixture
scope: "test"
created: $now
updated: $now
status: implemented
design-extended: false
reported-by: Test User
---

# Duplicate (archived copy)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (same filename in tasks/ and archive/)" "$rc" "1" || ok=false
    assert_contains "reports the collision" "$out" "duplicate task filename" || ok=false
    $ok
}

md1_footnote_blocks() {
    local tasks; tasks=$(fresh_tasks md1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_footnote.md" <<EOF
---
description: footnote fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Footnote user

Some claim with attribution.[^1]

[^1]: the attribution
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (footnotes are non-standard)" "$rc" "1" || ok=false
    assert_contains "names the footnote category" "$out" "footnote" || ok=false
    $ok
}

md2_wikilink_blocks() {
    local tasks; tasks=$(fresh_tasks md2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_wikilink.md" <<'EOF'
---
description: wikilink fixture
scope: "test"
created: PLACEHOLDER
updated: PLACEHOLDER
status: open
reported-by: Test User
---

# Wikilink user

See [[Some Page]] for more.
EOF
    # Stamp created/updated after the literal heredoc so the [[...]] stays
    # verbatim (no shell expansion) while timestamps remain current.
    sed -i.bak "s/PLACEHOLDER/$now/g" "$tasks/test_wikilink.md" && rm -f "$tasks/test_wikilink.md.bak"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (wikilinks are an Obsidian extension)" "$rc" "1" || ok=false
    assert_contains "names the Obsidian extension" "$out" "Obsidian extension" || ok=false
    $ok
}

sc1_unquoted_scope_real_dir_clean() {
    local tasks; tasks=$(fresh_tasks sc1)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/src"   # project-root-relative dir the scope points at
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/src_real-scope.md" <<EOF
---
description: unquoted scope pointing at a real dir
scope: src
created: $now
updated: $now
status: open
reported-by: Test User
---

# Real scope
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (scope resolves under project root)" "$rc" "0" || ok=false
    assert_not_contains "no scope finding" "$out" "scope" || ok=false
    $ok
}

sc2_unquoted_scope_missing_blocks() {
    local tasks; tasks=$(fresh_tasks sc2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_badscope.md" <<EOF
---
description: unquoted scope pointing nowhere
scope: nope-dir
created: $now
updated: $now
status: open
reported-by: Test User
---

# Missing scope path
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (scope path does not exist)" "$rc" "1" || ok=false
    assert_contains "explains the missing path" "$out" "does not exist under project root" || ok=false
    $ok
}

sc3_unquoted_scope_escape_blocks() {
    local tasks; tasks=$(fresh_tasks sc3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_escape.md" <<EOF
---
description: scope escaping the project root
scope: ../outside
created: $now
updated: $now
status: open
reported-by: Test User
---

# Escaping scope
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (scope escapes project root)" "$rc" "1" || ok=false
    assert_contains "explains the escape" "$out" "escapes the project root" || ok=false
    $ok
}

sc4_quoted_empty_scope_blocks() {
    local tasks; tasks=$(fresh_tasks sc4)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_emptyscope.md" <<EOF
---
description: quoted-but-empty scope
scope: ""
created: $now
updated: $now
status: open
reported-by: Test User
---

# Empty scope
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (quoted scope is empty)" "$rc" "1" || ok=false
    assert_contains "explains the empty label" "$out" "quoted but empty" || ok=false
    $ok
}

sz1_oversized_page_warns() {
    local tasks; tasks=$(fresh_tasks sz1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    {
        cat <<EOF
---
description: oversized page fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Oversized task
EOF
        local i
        for i in $(seq 1 320); do printf 'filler line %s\n' "$i"; done
    } > "$tasks/test_big.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (oversize is warn, not blocking)" "$rc" "0" || ok=false
    assert_contains "suggests splitting" "$out" "split into multiple tasks" || ok=false
    $ok
}

c1_fully_valid_task_is_clean() {
    local tasks; tasks=$(fresh_tasks c1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_good.md" <<EOF
---
description: a fully valid task
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# A clean task

Body with a title and sensible content.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (no issues)" "$rc" "0" || ok=false
    assert_contains "reports a clean tree" "$out" "clean — no issues" || ok=false
    $ok
}

# Soft-pointer rule: a line-number position claim warns, never blocks.
# The warn fixture carries the historical `path:N` shape plus every
# broadened shape from the hardening task: capitalized prose claims,
# tilde prose claims, path-then-tilde, and a parenthesized tilde range.
sp1_position_claims_warn() {
    local tasks; tasks=$(fresh_tasks sp1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_position.md" <<EOF
---
description: line-number position claim fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Position-claim user

The guard sits in \`deployment.sh:242\` and the matcher around lines 95-105.
Audit notes cite Lines 241-242 and Line 1532 in old drafts.
The stale range sat at (~158-188), with the source named as SKILL.md ~734.
The summary says currently line ~18 and around line ~554.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "soft-pointer" <<<"$out")
    local ok=true
    assert_eq "exit 0 (position claim is warn, not blocking)" "$rc" "0" || ok=false
    assert_contains "warns on the path claim, naming the match" "$out" "deployment.sh:242" || ok=false
    assert_contains "warns on the prose claim, naming the match" "$out" "around lines 9" || ok=false
    assert_contains "warns on capital Lines range" "$out" "Lines 241-242" || ok=false
    assert_contains "warns on capital Line claim" "$out" "Line 1532" || ok=false
    assert_contains "warns on parenthesized tilde range" "$out" "(~158-188)" || ok=false
    assert_contains "warns on path tilde claim" "$out" "SKILL.md ~734" || ok=false
    assert_contains "warns on line tilde claim" "$out" "line ~18" || ok=false
    assert_contains "warns on around line tilde claim" "$out" "around line ~554" || ok=false
    assert_contains "names the soft-pointer category" "$out" "soft-pointer" || ok=false
    assert_eq "exactly the eight warn findings" "$count" "8" || ok=false
    $ok
}

# The quiet fixture carries the dominant false-positive sources the
# design must keep silent: a host:port, a trailing `N lines` size count,
# a timestamp, and a fenced block whose contents WOULD warn if inline —
# proving fence-skip. None may produce a soft-pointer finding.
sp2_silent_shapes_stay_quiet() {
    local tasks; tasks=$(fresh_tasks sp2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_quiet.md" <<EOF
---
description: soft-pointer false-positive guard fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Quiet shapes

The server binds localhost:8080 and the log grows past 300 lines by 13:40:10.
The sample payload is 512 bytes locally and 100 MB remotely.

\`\`\`text
deployment.sh:242    line 42    around lines 95-105
\`\`\`
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (no blocking findings)" "$rc" "0" || ok=false
    assert_not_contains "no soft-pointer finding fires" "$out" "soft-pointer" || ok=false
    $ok
}

sp3_tilde_range_warns_but_size_extent_stays_quiet() {
    local tasks; tasks=$(fresh_tasks sp3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_tilde-size.md" <<EOF
---
description: tilde soft-pointer and size extent fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Tilde range user

The stale pointer was (~42-57), while the fixture payload is ~16 KB.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "soft-pointer" <<<"$out")
    local ok=true
    assert_eq "exit 0 (tilde position claim is warn, not blocking)" "$rc" "0" || ok=false
    assert_contains "warns on the tilde range" "$out" "(~42-57)" || ok=false
    assert_not_contains "does not warn on the size extent" "$out" "~16 KB" || ok=false
    assert_eq "exactly one soft-pointer finding" "$count" "1" || ok=false
    $ok
}

###############################################################################
# Repeated-link rule: one local target linked more than once warns.
###############################################################################

rl1_two_links_one_target_warns() {
    local tasks; tasks=$(fresh_tasks rl1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_once.md" <<EOF
---
description: single-link sibling for repeated-link floor fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Once target
EOF
    emit "$tasks/test_twice.md" <<EOF
---
description: two links to one sibling produce one repeated-link warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Twice linker

Context cites [Once target](test_once.md) as background.
Approach edits [Once target](test_once.md) again.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "repeated-link" <<<"$out")
    local ok=true
    assert_eq "exit 0 (repeated-link is warn, not blocking)" "$rc" "0" || ok=false
    assert_eq "exactly one repeated-link finding" "$count" "1" || ok=false
    assert_contains "names the target" "$out" "test_once.md" || ok=false
    assert_contains "names the count of 2" "$out" "linked 2 times" || ok=false
    assert_contains "frames organic growth" "$out" "grown organically" || ok=false
    assert_contains "suggests re-reading to regroup" "$out" "re-read those sections" || ok=false
    $ok
}

rl2_one_link_stays_quiet() {
    local tasks; tasks=$(fresh_tasks rl2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_once.md" <<EOF
---
description: single-link target for repeated-link floor fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Once target
EOF
    emit "$tasks/test_single.md" <<EOF
---
description: one link to a sibling produces no repeated-link warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Single linker

See [Once target](test_once.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (single link is clean)" "$rc" "0" || ok=false
    assert_not_contains "no repeated-link finding" "$out" "repeated-link" || ok=false
    $ok
}

rl3_seven_links_stronger_hint() {
    local tasks; tasks=$(fresh_tasks rl3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_once.md" <<EOF
---
description: seven-link target for repeated-link strength fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Once target
EOF
    emit "$tasks/test_seven.md" <<EOF
---
description: seven links to one sibling produce a stronger-hint warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Seven linker

[a](test_once.md) [b](test_once.md) [c](test_once.md) [d](test_once.md)
[e](test_once.md) [f](test_once.md) [g](test_once.md)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "repeated-link" <<<"$out")
    local ok=true
    assert_eq "exit 0 (repeated-link is warn, not blocking)" "$rc" "0" || ok=false
    assert_eq "exactly one repeated-link finding" "$count" "1" || ok=false
    assert_contains "names the count of 7" "$out" "linked 7 times" || ok=false
    assert_contains "frames a stronger hint" "$out" "a strong hint" || ok=false
    assert_contains "states hint strengthens with count" "$out" "strengthens with the count" || ok=false
    $ok
}

rl4_normalized_path_prefixes_collapse() {
    local tasks; tasks=$(fresh_tasks rl4)
    local root; root=$(dirname "$tasks")
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    mkdir -p "$root/shared"
    emit "$root/shared/target.md" <<EOF
# Shared target
EOF
    emit "$tasks/test_prefixes.md" <<EOF
---
description: two relative prefixes to one file collapse to one warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Prefix linker

Page-relative path: [Shared](../shared/target.md).
Project-root path: [Shared again](shared/target.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "repeated-link" <<<"$out")
    local ok=true
    assert_eq "exit 0 (repeated-link is warn, not blocking)" "$rc" "0" || ok=false
    assert_eq "exactly one repeated-link finding" "$count" "1" || ok=false
    assert_contains "names the count of 2" "$out" "linked 2 times" || ok=false
    assert_contains "names the shared target" "$out" "shared/target.md" || ok=false
    $ok
}

rl5_every_target_kind_counts() {
    local tasks; tasks=$(fresh_tasks rl5)
    local root; root=$(dirname "$tasks")
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    mkdir -p "$root/plugins/demo/skills/demo/scripts" "$root/wiki"
    emit "$tasks/test_sibling.md" <<EOF
---
description: sibling task that never links back
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Sibling target
EOF
    emit "$root/plugins/demo/skills/demo/SKILL.md" <<EOF
# Demo skill
EOF
    emit "$root/wiki/page.md" <<EOF
# Wiki page
EOF
    emit "$root/plugins/demo/skills/demo/scripts/helper.sh" <<EOF
#!/usr/bin/env bash
true
EOF
    emit "$root/plugins/demo/plugin.json" <<EOF
{"name":"demo"}
EOF
    emit "$tasks/test_kinds.md" <<EOF
---
description: every local target kind counted twice yields five warns
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Kind linker

Sibling: [a](test_sibling.md) and [b](test_sibling.md).
Skill: [c](../plugins/demo/skills/demo/SKILL.md) and [d](../plugins/demo/skills/demo/SKILL.md).
Wiki: [e](../wiki/page.md) and [f](../wiki/page.md).
Script: [g](../plugins/demo/skills/demo/scripts/helper.sh) and [h](../plugins/demo/skills/demo/scripts/helper.sh).
Manifest: [i](../plugins/demo/plugin.json) and [j](../plugins/demo/plugin.json).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "repeated-link" <<<"$out")
    local ok=true
    assert_eq "exit 0 (repeated-link is warn, not blocking)" "$rc" "0" || ok=false
    assert_eq "five repeated-link findings" "$count" "5" || ok=false
    assert_contains "counts sibling task" "$out" "test_sibling.md" || ok=false
    assert_contains "counts SKILL.md" "$out" "SKILL.md" || ok=false
    assert_contains "counts wiki page" "$out" "wiki/page.md" || ok=false
    assert_contains "counts scripts helper" "$out" "helper.sh" || ok=false
    assert_contains "counts plugin.json" "$out" "plugin.json" || ok=false
    $ok
}

rl6_nine_distinct_targets_stay_quiet() {
    local tasks; tasks=$(fresh_tasks rl6)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local i
    for i in 1 2 3 4 5 6 7 8 9; do
        emit "$tasks/test_t${i}.md" <<EOF
---
description: distinct target $i for breadth-not-repeat fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Target $i
EOF
    done
    emit "$tasks/test_breadth.md" <<EOF
---
description: nine distinct one-each links produce no repeated-link warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Breadth linker

[1](test_t1.md) [2](test_t2.md) [3](test_t3.md) [4](test_t4.md) [5](test_t5.md)
[6](test_t6.md) [7](test_t7.md) [8](test_t8.md) [9](test_t9.md)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (breadth is clean)" "$rc" "0" || ok=false
    assert_not_contains "no repeated-link finding" "$out" "repeated-link" || ok=false
    $ok
}

rl7_fenced_links_do_not_count() {
    local tasks; tasks=$(fresh_tasks rl7)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_once.md" <<EOF
---
description: fenced-only target for fence-skip fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Once target
EOF
    emit "$tasks/test_fenced.md" <<EOF
---
description: links only inside a fence produce no repeated-link warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Fenced linker

\`\`\`markdown
[a](test_once.md)
[b](test_once.md)
\`\`\`
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (fenced links skipped)" "$rc" "0" || ok=false
    assert_not_contains "no repeated-link finding" "$out" "repeated-link" || ok=false
    $ok
}

rl8_external_and_mailto_skipped() {
    local tasks; tasks=$(fresh_tasks rl8)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_external.md" <<EOF
---
description: https and mailto repeats produce no repeated-link warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# External linker

[site](https://example.com/docs) and [site again](https://example.com/docs).
[mail](mailto:dev@example.com) and [mail again](mailto:dev@example.com).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (external and mailto skipped)" "$rc" "0" || ok=false
    assert_not_contains "no repeated-link finding" "$out" "repeated-link" || ok=false
    $ok
}

###############################################################################
# design-extended: optional field, typed when present, absence reads as false
###############################################################################

de1_absent_design_extended_is_clean() {
    local tasks; tasks=$(fresh_tasks de1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_live.md" <<EOF
---
description: implemented task predating the design-extended field
scope: "test"
created: $now
updated: $now
status: implemented
reported-by: Test User
implemented-by: Test User
---

# Implemented without the field
EOF
    emit "$tasks/archive/test_closed.md" <<EOF
---
description: archived finished task predating the design-extended field
scope: "test"
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Finished without the field
EOF
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (absence reads as false, no backfill needed)" "$rc" "0" || ok=false
    assert_not_contains "no design-extended finding" "$out" "design-extended" || ok=false
    $ok
}

de2_non_boolean_design_extended_blocks() {
    local tasks; tasks=$(fresh_tasks de2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_bad.md" <<EOF
---
description: implemented task with a non-boolean design-extended value
scope: "test"
created: $now
updated: $now
status: implemented
reported-by: Test User
implemented-by: Test User
design-extended: yes-it-did
---

# Non-boolean design-extended
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (a present value must be boolean)" "$rc" "1" || ok=false
    assert_contains "names the field" "$out" "design-extended must be boolean" || ok=false
    $ok
}

de3_boolean_design_extended_is_clean() {
    local tasks; tasks=$(fresh_tasks de3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_true.md" <<EOF
---
description: implemented task recording a positive design verdict
scope: "test"
created: $now
updated: $now
status: implemented
reported-by: Test User
implemented-by: Test User
design-extended: true
---

# Design extended
EOF
    emit "$tasks/archive/test_false.md" <<EOF
---
description: finished task recording a negative design verdict
scope: "test"
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
design-extended: false
---

# Design untouched
EOF
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (both booleans accepted)" "$rc" "0" || ok=false
    assert_not_contains "no design-extended finding" "$out" "design-extended" || ok=false
    $ok
}

am1_tracked_move_records_a_rename() {
    local tasks; tasks=$(fresh_tasks am1)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_tracked-close-out.md" "$now"
    git_commit_fixture "$root" "Origin Author" "seed: tracked task file"
    local branch
    branch=$(archive_move "$root" "tasks/test_tracked-close-out.md" "tasks/archive/test_tracked-close-out.md")
    local porcelain; porcelain=$(git -C "$root" status --porcelain)
    git_commit_fixture "$root" "Archive Mover" "archive: finish task"
    local followed
    followed=$(git -C "$root" log --follow --format=%s -- tasks/archive/test_tracked-close-out.md)
    local ok=true
    assert_eq "tracked probe takes the git mv branch" "$branch" "git mv" || ok=false
    assert_contains "status reports a rename" "$porcelain" \
        "R  tasks/test_tracked-close-out.md -> tasks/archive/test_tracked-close-out.md" || ok=false
    assert_contains "log --follow reaches the origin commit" "$followed" "seed: tracked task file" || ok=false
    assert_eq "archived file exists" "$([[ -f $tasks/archive/test_tracked-close-out.md ]] && echo yes)" "yes" || ok=false
    $ok
}

am2_untracked_move_takes_the_fallback() {
    local tasks; tasks=$(fresh_tasks am2)
    local root; root=$(dirname "$tasks")
    git -C "$root" init -q
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_never-committed.md" "$now"
    local branch rc
    branch=$(archive_move "$root" "tasks/test_never-committed.md" "tasks/archive/test_never-committed.md"); rc=$?
    local porcelain; porcelain=$(git -C "$root" status --porcelain)
    local ok=true
    assert_eq "fallback move exits 0" "$rc" "0" || ok=false
    assert_eq "untracked probe takes the plain mv branch" "$branch" "mv" || ok=false
    assert_eq "archived file exists" "$([[ -f $tasks/archive/test_never-committed.md ]] && echo yes)" "yes" || ok=false
    assert_eq "live path is gone" "$([[ -e $tasks/test_never-committed.md ]] || echo gone)" "gone" || ok=false
    assert_not_contains "no rename recorded for an untracked file" "$porcelain" "R  tasks/" || ok=false
    $ok
}

am3_probe_fails_outside_a_repository() {
    local base; base=$(ext_tmp)
    if in_git_tree "$base"; then
        log "    [temp dir sits inside a git tree - no-repository probe N/A]"
        return 2
    fi
    local tasks="$base/tasks"
    mkdir -p "$tasks/archive"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_no-repo.md" "$now"
    local branch rc
    branch=$(archive_move "$base" "tasks/test_no-repo.md" "tasks/archive/test_no-repo.md"); rc=$?
    local ok=true
    assert_eq "fallback move exits 0 with no repository" "$rc" "0" || ok=false
    assert_eq "one probe also covers the no-repository case" "$branch" "mv" || ok=false
    assert_eq "archived file exists" "$([[ -f $tasks/archive/test_no-repo.md ]] && echo yes)" "yes" || ok=false
    $ok
}

###############################################################################
# Run scenarios
###############################################################################

scenario l1 "lint: project-root-relative body link resolves"   l1_project_root_fallback_resolves
scenario l2 "lint: link missing under both roots blocks"       l2_missing_under_both_roots_blocks
scenario l3 "lint: sibling-task link still resolves"           l3_sibling_task_link_resolves

scenario d1 "discover: git toplevel resolution"                d1_git_toplevel_resolves
scenario d2 "discover: missing tasks/ signals exit 1"          d2_missing_tasks_exits_one
scenario d3 "discover: project-marker walk from a subdir"      d3_marker_walk_from_subdir
scenario d4 "discover: bad argument exits 2"                    d4_bad_argument_exits_two
scenario d5 "discover: --help exits 0"                          d5_help_exits_zero

scenario i1 "init: scaffolds tasks/ and archive/"              i1_scaffolds_tasks_and_archive
scenario i2 "init: idempotent on an existing tree"             i2_idempotent_on_existing
scenario i3 "init: refuses a non-directory target"            i3_refuses_non_directory_target
scenario i4 "init: missing PATH argument exits 2"              i4_no_argument_exits_two
scenario i5 "init: --help exits 0"                             i5_help_exits_zero

scenario n1  "lint: bad filename blocks"                       n1_bad_filename_blocks
scenario f1  "lint: missing frontmatter blocks"                f1_missing_frontmatter_blocks
scenario f2  "lint: missing required field blocks"             f2_missing_required_field_blocks
scenario f3  "lint: invalid status blocks"                     f3_invalid_status_blocks
scenario f4  "lint: non-ISO datetime warns"                    f4_non_iso_datetime_warns
scenario f5  "lint: missing H1 title warns"                    f5_missing_h1_warns
scenario loc1 "lint: archived non-terminal silent by default"  loc1_archived_non_terminal_silent_by_default
scenario loc2 "lint: finished task in tasks root blocks"       loc2_finished_in_root_blocks
scenario loc3 "lint: ready task in tasks root is clean"        loc3_ready_in_root_clean
scenario loc4 "lint: archive mode migrates legacy status"      loc4_archived_non_terminal_migrates_in_archive_mode
scenario prov1 "lint: missing reported-by blocks"              prov1_missing_reported_by_blocks
scenario prov2 "lint: implemented requires implemented-by"     prov2_implemented_requires_implemented_by
scenario prov3 "lint: deferred omits implemented-by cleanly"   prov3_deferred_without_implemented_by_clean
scenario prov4 "lint: reported-by from first commit author"    prov4_reported_by_uses_first_commit_author
scenario prov5 "lint: implemented-by from archive move author" prov5_archived_finished_implemented_by_uses_rename_author
scenario col1 "lint: duplicate filename across roots blocks"   col1_duplicate_name_across_roots_blocks
scenario md1 "lint: footnote blocks"                           md1_footnote_blocks
scenario md2 "lint: wikilink blocks"                           md2_wikilink_blocks
scenario sc1 "lint: unquoted scope at a real dir is clean"     sc1_unquoted_scope_real_dir_clean
scenario sc2 "lint: unquoted scope missing path blocks"        sc2_unquoted_scope_missing_blocks
scenario sc3 "lint: unquoted scope escaping root blocks"       sc3_unquoted_scope_escape_blocks
scenario sc4 "lint: quoted-but-empty scope blocks"             sc4_quoted_empty_scope_blocks
scenario sz1 "lint: oversized page warns"                      sz1_oversized_page_warns
scenario c1  "lint: fully valid task is clean"                 c1_fully_valid_task_is_clean
scenario sp1 "lint: line-number position claims warn"          sp1_position_claims_warn
scenario sp2 "lint: silent shapes stay quiet (fence-skip)"     sp2_silent_shapes_stay_quiet
scenario sp3 "lint: tilde range warns while size extent skips"  sp3_tilde_range_warns_but_size_extent_stays_quiet

scenario rl1 "lint: two links to one target warn"               rl1_two_links_one_target_warns
scenario rl2 "lint: one link to a target stays quiet"           rl2_one_link_stays_quiet
scenario rl3 "lint: seven links frame a stronger hint"          rl3_seven_links_stronger_hint
scenario rl4 "lint: normalized path prefixes collapse"          rl4_normalized_path_prefixes_collapse
scenario rl5 "lint: every local target kind counts"             rl5_every_target_kind_counts
scenario rl6 "lint: nine distinct targets stay quiet"           rl6_nine_distinct_targets_stay_quiet
scenario rl7 "lint: fenced links do not count"                  rl7_fenced_links_do_not_count
scenario rl8 "lint: external and mailto targets skipped"        rl8_external_and_mailto_skipped

scenario de1 "lint: absent design-extended is clean"           de1_absent_design_extended_is_clean
scenario de2 "lint: non-boolean design-extended blocks"        de2_non_boolean_design_extended_blocks
scenario de3 "lint: boolean design-extended is clean"          de3_boolean_design_extended_is_clean

scenario am1 "archive: tracked move records a rename"          am1_tracked_move_records_a_rename
scenario am2 "archive: untracked move takes the fallback"      am2_untracked_move_takes_the_fallback
scenario am3 "archive: one probe covers a missing repository"  am3_probe_fails_outside_a_repository

###############################################################################
# Summary
###############################################################################

log ""
log "================================================================"
log "  $((PASS+FAIL+SKIP)) scenarios — $PASS pass, $FAIL fail, $SKIP skip"
if (( FAIL > 0 )); then
    log "  failed: ${FAILED_IDS[*]}"
fi
log "================================================================"

if (( FAIL > 0 )); then
    exit 1
fi
exit 0
