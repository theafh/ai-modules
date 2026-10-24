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
#   l* lint.py body link resolution (check_local_links): on a default /
#      --include-archive run the walk covers every repo markdown file
#      (git ls-files -z --exclude-standard when project_root is the git
#      toplevel or a subdirectory git does not ignore, so non-ASCII names
#      stay in; Makefile prune-shaped EXCLUDE layered on top or used
#      alone outside git, and ignored whole when it carries a find action
#      such as -exec or -delete; else rglob skipping .git/); any in-repo
#      target (file or directory) is checked; :// / mailto: / outside-repo
#      targets stay silent; a leading-/ miss is repo-root-relative;
#      fences, list-nested fences included, inline code, autolinks, and
#      raw HTML are scrubbed, while four-column-indented list content
#      keeps its links; under --file, link checks
#      stay scoped to the named task. A `.md` link still resolves against
#      the linking file's directory and, as a fallback, against the
#      project root.
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

# run_lint_in <dir> <tasks> [args...] -> echoes "<exit>|<combined output>",
# running lint.py with CWD set to <dir> so a relative `--file` value is
# resolved against that directory as well as against <tasks>.
run_lint_in() {
    local dir=$1 tasks=$2 out rc
    shift 2 || true
    out=$(cd "$dir" && python3 "$LINT" "$tasks" "$@" 2>&1) && rc=0 || rc=$?
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

l4_wiki_dangling_task_link_blocks() {
    # A wiki page linking a missing tasks/ path produces a broken-link
    # finding naming that wiki page on a default run.
    local tasks; tasks=$(fresh_tasks l4)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/wiki"
    cat > "$root/wiki/page.md" <<'EOF'
# Wiki page

See [the task](../tasks/missing_task.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (wiki dangling task link blocks)" "$rc" "1" || ok=false
    assert_contains "broken-link finding fires" "$out" "broken-link" || ok=false
    assert_contains "finding names the wiki page" "$out" "wiki/page.md" || ok=false
    $ok
}

l5_non_task_md_skips_other_checks() {
    # A non-task .md under the repo root with no task frontmatter must
    # not fire footnote / wikilink / soft-pointer / repeated-link checks;
    # only the link check runs on it.
    local tasks; tasks=$(fresh_tasks l5)
    local root; root=$(dirname "$tasks")
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_anchor.md" "$now"
    cat > "$root/notes.md" <<'EOF'
# Notes

A footnote[^1] and a [[wikilink]] and path.py:12 and line 9.

See [one](tasks/test_anchor.md) and [two](tasks/test_anchor.md) again.

[^1]: attribution
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (non-task md only runs link check)" "$rc" "0" || ok=false
    assert_not_contains "no footnote finding on non-task md" "$out" "footnote" || ok=false
    assert_not_contains "no wikilink finding on non-task md" "$out" "wikilink" || ok=false
    assert_not_contains "no soft-pointer finding on non-task md" "$out" "soft-pointer" || ok=false
    assert_not_contains "no repeated-link finding on non-task md" "$out" "repeated-link" || ok=false
    assert_not_contains "no broken-link when targets exist" "$out" "broken-link" || ok=false
    $ok
}

l6_non_md_target_existence() {
    # Existing non-.md in-repo target is clean; missing non-.md blocks.
    local tasks; tasks=$(fresh_tasks l6)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/scripts"
    : > "$root/scripts/helper.sh"
    write_linking_task "$tasks" "test_ok-script.md" "scripts/helper.sh"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (existing non-.md target resolves)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link for existing script" "$out" "broken-link" || ok=false

    write_linking_task "$tasks" "test_missing-script.md" "scripts/missing.sh"
    ret=$(run_lint "$tasks")
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "exit 1 (missing non-.md target blocks)" "$rc" "1" || ok=false
    assert_contains "broken-link for missing script" "$out" "broken-link" || ok=false
    $ok
}

l7_outbound_targets_silent() {
    # https://, mailto:, an existing absolute path outside the repo, and
    # climb-past-root stay silent. A non-existing leading-/ path is
    # repo-root-relative (see l26) and is not this silence case.
    local tasks; tasks=$(fresh_tasks l7)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local abs_existing=/tmp
    [[ -e "$abs_existing" ]] || abs_existing=/
    cat > "$tasks/test_outbound.md" <<EOF
---
description: outbound-link silence fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Outbound silence fixture

- [web](https://example.com/path)
- [mail](mailto:user@example.com)
- [abs]($abs_existing)
- [climb](../../../../tmp/task_lint_outside_climb_$$/nope.md)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (outbound targets silent)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link for outbound targets" "$out" "broken-link" || ok=false
    $ok
}

l8_directory_target_resolves() {
    local tasks; tasks=$(fresh_tasks l8)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/docs/chapter"
    write_linking_task "$tasks" "test_dir-link.md" "docs/chapter"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (directory target resolves)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link for directory" "$out" "broken-link" || ok=false
    $ok
}

l9_makefile_exclude_prunes_dangling() {
    # A uniquely named directory pruned by Makefile EXCLUDE contributes
    # no finding for a dangling in-repo link under it.
    local tasks; tasks=$(fresh_tasks l9)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/zz_lint_exclude_unique_l9"
    cat > "$root/zz_lint_exclude_unique_l9/dangling.md" <<'EOF'
# Excluded dangling

See [missing](nope_missing_target.md).
EOF
    cat > "$root/Makefile" <<'EOF'
EXCLUDE     := -path ./.git -prune -o \
               -path './zz_lint_exclude_unique_l9' -prune -o
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (EXCLUDE prunes dangling tree)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link from excluded tree" "$out" "broken-link" || ok=false

    ret=$(run_lint "$tasks" --include-archive)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "exit 0 (--include-archive also respects EXCLUDE)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link under --include-archive" "$out" "broken-link" || ok=false
    $ok
}

l10_no_exclude_reports_dangling() {
    # No Makefile EXCLUDE (and no git toplevel here): a dangling in-repo
    # link outside .git/ blocks via the rglob fallback.
    local tasks; tasks=$(fresh_tasks l10)
    local root; root=$(dirname "$tasks")
    # Explicitly no Makefile (fresh_tasks already leaves the root empty).
    rm -f "$root/Makefile"
    mkdir -p "$root/extra"
    cat > "$root/extra/notes.md" <<'EOF'
# Extra notes

See [missing](does_not_exist.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (no EXCLUDE: dangling blocks)" "$rc" "1" || ok=false
    assert_contains "broken-link finding fires" "$out" "broken-link" || ok=false
    assert_contains "finding names the extra page" "$out" "extra/notes.md" || ok=false

    ret=$(run_lint "$tasks" --include-archive)
    rc=${ret%%|*}; out=${ret#*|}
    assert_eq "exit 1 (--include-archive same without EXCLUDE)" "$rc" "1" || ok=false
    assert_contains "broken-link under --include-archive" "$out" "broken-link" || ok=false
    $ok
}

l24_gitignore_skips_node_modules() {
    # Inside a real git toplevel, a gitignored node_modules README with a
    # dangling relative link contributes no finding. Stage outside the
    # surrounding ai-modules checkout so project_root is the git toplevel.
    local root; root=$(ext_tmp)
    git -C "$root" init -q
    printf '%s\n' 'node_modules/' > "$root/.gitignore"
    mkdir -p "$root/tasks/archive" "$root/node_modules/pkg"
    write_task "$root/tasks" "test_gitignore-walk.md" "2026-01-01T00:00:00"
    cat > "$root/node_modules/pkg/README.md" <<'EOF'
# Vendored package

See [docs](docs/api.md).
EOF
    local ret; ret=$(run_lint "$root/tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (gitignored node_modules silent)" "$rc" "0" || ok=false
    assert_not_contains "no broken-link from node_modules" "$out" "node_modules" || ok=false
    assert_not_contains "no broken-link finding at all" "$out" "broken-link" || ok=false
    $ok
}

l25_non_prune_exclude_keeps_check() {
    # A Makefile EXCLUDE that is not prune-shaped must not silence the
    # link check. Outside git, the rglob fallback still sees README.md.
    local tasks; tasks=$(fresh_tasks l25)
    local root; root=$(dirname "$tasks")
    cat > "$root/Makefile" <<'EOF'
EXCLUDE := -name '*.tmp'
EOF
    cat > "$root/README.md" <<'EOF'
# Root readme

See [missing](does_not_exist.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (non-prune EXCLUDE still checks)" "$rc" "1" || ok=false
    assert_contains "broken-link still fires" "$out" "broken-link" || ok=false
    assert_contains "finding names README" "$out" "README.md" || ok=false
    $ok
}

l26_leading_slash_repo_root_relative() {
    # A leading-/ destination that is not an existing absolute path is
    # checked as repository-root-relative.
    local tasks; tasks=$(fresh_tasks l26)
    local root; root=$(dirname "$tasks")
    cat > "$root/README.md" <<'EOF'
# Root readme

See [abs](/docs/missing.md) and [rel](docs/missing.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (leading-slash miss blocks)" "$rc" "1" || ok=false
    assert_contains "abs label in finding" "$out" "'abs'" || ok=false
    assert_contains "rel label in finding" "$out" "'rel'" || ok=false
    $ok
}

l11_file_scope_ignores_other_md() {
    # Under --file, a dangling link in a different repo markdown file is
    # ignored; a dangling link in the named task still reports.
    local tasks; tasks=$(fresh_tasks l11)
    local root; root=$(dirname "$tasks")
    mkdir -p "$root/wiki"
    cat > "$root/wiki/other.md" <<'EOF'
# Other

See [missing](../tasks/ghost.md).
EOF
    write_linking_task "$tasks" "test_named.md" "ghost_named.md"
    local ret; ret=$(run_lint "$tasks" --file "$tasks/test_named.md")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (named task dangling still blocks)" "$rc" "1" || ok=false
    assert_contains "broken-link for named task" "$out" "broken-link" || ok=false
    assert_contains "finding names the scoped task" "$out" "test_named.md" || ok=false
    assert_not_contains "wiki other.md stays out of --file report" "$out" "other.md" || ok=false
    $ok
}

l12_fenced_link_ignored() {
    local tasks; tasks=$(fresh_tasks l12)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_fence.md" <<EOF
---
description: fenced-link silence fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Fenced link fixture

~~~text
See [tilde missing](nope_in_tilde_fence.md).
~~~

\`\`\`\`text
See [long missing](nope_in_long_fence.md).
\`\`\`
Still fenced [after short run](nope_after_short_run.md).
\`\`\`\`

~~
See [live after invalid fence](missing_after_invalid_fence.md).
~~
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    assert_eq "exit 1 (only link outside valid fences blocks)" "$rc" "1" || ok=false
    assert_eq "exactly one broken-link outside fences" "$count" "1" || ok=false
    assert_contains "invalid two-tilde run is ordinary text" "$out" "missing_after_invalid_fence.md" || ok=false
    assert_not_contains "tilde-fenced link is ignored" "$out" "nope_in_tilde_fence.md" || ok=false
    assert_not_contains "long backtick fence is ignored" "$out" "nope_in_long_fence.md" || ok=false
    assert_not_contains "shorter run does not close long fence" "$out" "nope_after_short_run.md" || ok=false
    $ok
}

l13_inline_code_link_ignored() {
    local tasks; tasks=$(fresh_tasks l13)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_inline.md" <<EOF
---
description: inline-code-link silence fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Inline code link fixture

Use \`\`[missing](nope_in_double_inline.md)\`\` as an example.

An unmatched \`\` opener leaves [live](missing_after_unmatched_span.md) visible.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    assert_eq "exit 1 (only link after unmatched code run blocks)" "$rc" "1" || ok=false
    assert_eq "exactly one broken-link outside code span" "$count" "1" || ok=false
    assert_contains "unmatched opener leaves following link live" "$out" "missing_after_unmatched_span.md" || ok=false
    assert_not_contains "matching double-backtick span is ignored" "$out" "nope_in_double_inline.md" || ok=false
    $ok
}

l14_empty_labels_existing_and_missing() {
    local tasks; tasks=$(fresh_tasks l14)
    local root; root=$(dirname "$tasks")
    : > "$root/existing-empty.md"
    write_linking_task "$tasks" "test_empty-label.md" "missing-ordinary-control.md"
    printf '\n[](../existing-empty.md)\n[](missing-empty.md)\n' >> "$tasks/test_empty-label.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (empty-label missing target blocks)" "$rc" "1" || ok=false
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    assert_eq "exactly empty and ordinary missing links reported" "$count" "2" || ok=false
    assert_contains "empty-label missing target reported" "$out" "missing-empty.md" || ok=false
    assert_contains "ordinary control remains live" "$out" "missing-ordinary-control.md" || ok=false
    assert_not_contains "empty-label existing target stays clean" "$out" "link target missing: existing-empty.md" || ok=false
    $ok
}

l15_nested_labels_existing_and_missing() {
    local tasks; tasks=$(fresh_tasks l15)
    local root; root=$(dirname "$tasks")
    : > "$root/existing-nested.md"
    write_linking_task "$tasks" "test_nested-label.md" "missing-ordinary-control.md"
    printf '\n[outer [inner]](../existing-nested.md)\n[outer [inner]](missing-nested.md)\n' >> "$tasks/test_nested-label.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (nested-label missing target blocks)" "$rc" "1" || ok=false
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    assert_eq "exactly nested and ordinary missing links reported" "$count" "2" || ok=false
    assert_contains "nested-label missing target reported" "$out" "missing-nested.md" || ok=false
    assert_contains "ordinary control remains live" "$out" "missing-ordinary-control.md" || ok=false
    assert_not_contains "nested-label existing target stays clean" "$out" "link target missing: existing-nested.md" || ok=false
    $ok
}

l16_angle_destinations_existing_and_missing() {
    local tasks; tasks=$(fresh_tasks l16)
    local root; root=$(dirname "$tasks")
    : > "$root/existing angle.md"
    write_linking_task "$tasks" "test_angle-destination.md" "<existing angle.md>"
    printf '\n[missing](<missing angle.md>)\n' >> "$tasks/test_angle-destination.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (angle missing target blocks)" "$rc" "1" || ok=false
    assert_contains "complete angle destination reported" "$out" "missing angle.md" || ok=false
    assert_not_contains "angle existing target stays clean" "$out" "link target missing: tasks/existing angle.md" || ok=false
    $ok
}

l17_balanced_destinations_existing_and_missing() {
    local tasks; tasks=$(fresh_tasks l17)
    local root; root=$(dirname "$tasks")
    : > "$root/existing_(v1).md"
    write_linking_task "$tasks" "test_balanced-destination.md" "existing_(v1).md"
    printf '\n[missing](missing_(v1).md)\n' >> "$tasks/test_balanced-destination.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (balanced missing target blocks)" "$rc" "1" || ok=false
    assert_contains "complete balanced destination reported" "$out" "missing_(v1).md" || ok=false
    assert_not_contains "balanced existing target stays clean" "$out" "link target missing: tasks/existing_(v1).md" || ok=false
    $ok
}

l18_reference_links_existing_and_missing() {
    local tasks; tasks=$(fresh_tasks l18)
    local root; root=$(dirname "$tasks")
    : > "$root/existing-reference.md"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_reference-links.md" <<EOF
---
description: reference-link extraction fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Reference links

[existing full][exists] [existing collapsed][] [existing shortcut]
[missing full][missing] [missing collapsed][] [missing shortcut]

[exists]: ../existing-reference.md
[existing collapsed]: ../existing-reference.md
[existing shortcut]: ../existing-reference.md
[missing]: ../missing-reference.md
[missing collapsed]: ../missing-reference.md
[missing shortcut]: ../missing-reference.md
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (missing reference targets block)" "$rc" "1" || ok=false
    assert_contains "reference missing target reported" "$out" "missing-reference.md" || ok=false
    assert_not_contains "reference existing target stays clean" "$out" "link target missing: existing-reference.md" || ok=false
    $ok
}

l19_reference_syntax_escapes_and_entities() {
    local tasks; tasks=$(fresh_tasks l19)
    local root; root=$(dirname "$tasks")
    : > "$root/existing&entity.md"
    : > "$root/existing[escape].md"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_reference-controls.md" <<EOF
---
description: reference syntax and escape controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Reference controls

[valid title][valid] [entity&amp;label] [escaped\[label] \\![escaped bang](missing-escaped-bang.md)
![image](missing-image.md) \\[escaped bracket](missing-escaped-bracket.md)
\\\\[even bracket](missing-even-bracket.md) \\\\![even bang image](missing-even-bang.md)
[junk][junk] [unterminated][unterminated]

[valid]: missing-valid-title.md "a valid title"
[entity&label]: ../existing&amp;entity.md
[escaped\[label]: ../existing\[escape\].md
[junk]: missing-junk.md trailing junk
[unterminated]: missing-unterminated.md "title
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (valid live links block)" "$rc" "1" || ok=false
    assert_eq "exactly valid title, escaped bang, and even bracket links report" "$count" "3" || ok=false
    assert_contains "valid titled definition resolves" "$out" "missing-valid-title.md" || ok=false
    assert_contains "escaped literal bang precedes a real link" "$out" "missing-escaped-bang.md" || ok=false
    assert_contains "even backslashes leave bracket unescaped" "$out" "missing-even-bracket.md" || ok=false
    assert_not_contains "real image opener stays ignored" "$out" "missing-image.md" || ok=false
    assert_not_contains "odd escaped bracket stays ignored" "$out" "missing-escaped-bracket.md" || ok=false
    assert_not_contains "even backslashes leave real image opener" "$out" "missing-even-bang.md" || ok=false
    assert_not_contains "trailing junk invalidates definition" "$out" "missing-junk.md" || ok=false
    assert_not_contains "unterminated title invalidates definition" "$out" "missing-unterminated.md" || ok=false
    assert_not_contains "entities decode in labels and destinations" "$out" "existing&entity.md" || ok=false
    assert_not_contains "escapes decode in labels and destinations" "$out" "existing[escape].md" || ok=false
    $ok
}

l20_nested_image_descriptions_are_excluded() {
    local tasks; tasks=$(fresh_tasks l20)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_nested-images.md" <<EOF
---
description: nested image description exclusion controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Nested image controls

![inline [hidden](missing-inline-inner.md)](missing-inline-image.png)
![full [hidden](missing-full-inner.md)][full-image]
![collapsed [hidden](missing-collapsed-inner.md)][]
![shortcut [hidden](missing-shortcut-inner.md)]
\![escaped [hidden](missing-escaped-inner.md)](missing-escaped-outer.md)
\\\\![even [hidden](missing-even-inner.md)](missing-even-image.png)
[live control](missing-live-control.md)

[full-image]: missing-full-image.png
[collapsed [hidden](missing-collapsed-definition.md)]: missing-collapsed-image.png
[shortcut [hidden](missing-shortcut-definition.md)]: missing-shortcut-image.png
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (escaped image opener and live control block)" "$rc" "1" || ok=false
    assert_eq "exactly escaped outer link and live control report" "$count" "2" || ok=false
    assert_contains "escaped bang preserves a real outer link" "$out" "missing-escaped-outer.md" || ok=false
    assert_contains "ordinary live-link control remains visible" "$out" "missing-live-control.md" || ok=false
    assert_not_contains "inline image destination stays excluded" "$out" "missing-inline-image.png" || ok=false
    assert_not_contains "nested inline image description stays excluded" "$out" "missing-inline-inner.md" || ok=false
    assert_not_contains "nested full-reference image description stays excluded" "$out" "missing-full-inner.md" || ok=false
    assert_not_contains "full-reference image destination stays excluded" "$out" "missing-full-image.png" || ok=false
    assert_not_contains "nested collapsed image description stays excluded" "$out" "missing-collapsed-inner.md" || ok=false
    assert_not_contains "collapsed image destination stays excluded" "$out" "missing-collapsed-image.png" || ok=false
    assert_not_contains "nested shortcut image description stays excluded" "$out" "missing-shortcut-inner.md" || ok=false
    assert_not_contains "shortcut image destination stays excluded" "$out" "missing-shortcut-image.png" || ok=false
    assert_not_contains "even backslashes preserve image exclusion" "$out" "missing-even-inner.md" || ok=false
    assert_not_contains "even-backslash image destination stays excluded" "$out" "missing-even-image.png" || ok=false
    $ok
}

l21_reference_definition_title_lines_are_excluded() {
    local tasks; tasks=$(fresh_tasks l21)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_reference-title-lines.md" <<EOF
---
description: reference definition title line controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Reference title line controls

[same-line use][same-line]
[continued use][continued]
[continued single use][continued-single]
[continued paren use][continued-paren]
[malformed use][malformed]
[live control](missing-live-control.md)

[same-line]: missing-same-line.md "title [hidden](missing-same-title-link.md)"
[continued]: missing-continued.md
  "title [hidden](missing-continued-title-link.md)"
[continued-single]: missing-continued-single.md
 'title [hidden](missing-single-title-link.md)'
[continued-paren]: missing-continued-paren.md
   (title [hidden][paren-title-link])
[malformed]: missing-malformed.md
  "unterminated [live](missing-malformed-title-link.md)
[paren-title-link]: missing-paren-title-link.md
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (reference targets and malformed control block)" "$rc" "1" || ok=false
    assert_eq "exactly five definitions, malformed live link, and control report" "$count" "7" || ok=false
    assert_contains "same-line titled definition resolves" "$out" "missing-same-line.md" || ok=false
    assert_contains "continued double-quoted definition resolves" "$out" "missing-continued.md" || ok=false
    assert_contains "continued single-quoted definition resolves" "$out" "missing-continued-single.md" || ok=false
    assert_contains "continued parenthesized definition resolves" "$out" "missing-continued-paren.md" || ok=false
    assert_contains "malformed continuation leaves definition valid" "$out" "missing-malformed.md" || ok=false
    assert_contains "malformed continuation remains live content" "$out" "missing-malformed-title-link.md" || ok=false
    assert_contains "ordinary live-link control remains visible" "$out" "missing-live-control.md" || ok=false
    assert_not_contains "same-line title content stays excluded" "$out" "missing-same-title-link.md" || ok=false
    assert_not_contains "continued double-quoted title stays excluded" "$out" "missing-continued-title-link.md" || ok=false
    assert_not_contains "continued single-quoted title stays excluded" "$out" "missing-single-title-link.md" || ok=false
    assert_not_contains "continued parenthesized title stays excluded" "$out" "missing-paren-title-link.md" || ok=false
    $ok
}

l22_url_spelled_destinations_normalize() {
    local tasks; tasks=$(fresh_tasks l22)
    local root; root=$(dirname "$tasks")
    : > "$root/existing file.md"
    : > "$root/existing.md"
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_url-spelled.md" <<EOF
---
description: percent-encoded and query destination controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# URL-spelled destinations

[encoded existing](../existing%20file.md)
[query existing](../existing.md?view=1)
[encoded missing](../missing%20file.md)
[query missing](../missing.md?view=1)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (missing URL-spelled targets block)" "$rc" "1" || ok=false
    assert_eq "exactly two missing URL-spelled targets report" "$count" "2" || ok=false
    assert_contains "percent-decoded missing path reported" "$out" "missing file.md" || ok=false
    assert_contains "query-stripped missing path reported" "$out" "missing.md" || ok=false
    assert_not_contains "percent-encoded existing target stays clean" "$out" "existing%20file.md" || ok=false
    assert_not_contains "query existing target stays clean" "$out" "existing.md?view=1" || ok=false
    assert_not_contains "decoded existing target not reported missing" "$out" "link target missing: existing file.md" || ok=false
    assert_not_contains "query-stripped existing target not reported missing" "$out" "link target missing: existing.md " || ok=false
    $ok
}

l23_literal_raw_constructs_ignored() {
    local tasks; tasks=$(fresh_tasks l23)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_literal-raw.md" <<EOF
---
description: autolink and raw HTML controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Literal and raw constructs

Autolink: <https://example.com/[label](missing-autolink.md)>

HTML: <span title="[label](missing-html.md)">text</span>

Real control: [live](missing-live-control.md)
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (live control blocks)" "$rc" "1" || ok=false
    assert_eq "exactly one live-control broken-link" "$count" "1" || ok=false
    assert_contains "ordinary live-link control remains visible" "$out" "missing-live-control.md" || ok=false
    assert_not_contains "autolink-embedded link stays ignored" "$out" "missing-autolink.md" || ok=false
    assert_not_contains "raw-html attribute link stays ignored" "$out" "missing-html.md" || ok=false
    $ok
}

l27_exclude_with_find_action_rejected() {
    # A prune-shaped EXCLUDE that also carries find actions is rejected as
    # a whole: no action runs, and the link check falls back to the rglob
    # walk, so a dangling README link still blocks.
    local tasks; tasks=$(fresh_tasks l27)
    local root; root=$(dirname "$tasks")
    printf '# Victim\n' > "$root/victim.md"
    cat > "$root/Makefile" <<'EOF'
EXCLUDE := -path ./.git -prune -o \
           -name README.md -exec touch l27_exec_sentinel ';' -o \
           -name victim.md -delete -o
EOF
    cat > "$root/README.md" <<'EOF'
# Root readme

See [missing](does_not_exist.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (rejected EXCLUDE keeps link check)" "$rc" "1" || ok=false
    assert_contains "broken-link still fires" "$out" "broken-link" || ok=false
    assert_contains "finding names README" "$out" "README.md" || ok=false
    if [[ -e "$root/l27_exec_sentinel" ]]; then
        echo "  FAIL: -exec from EXCLUDE ran (sentinel created)"; ok=false
    fi
    if [[ ! -e "$root/victim.md" ]]; then
        echo "  FAIL: -delete from EXCLUDE ran (victim.md removed)"; ok=false
    fi
    $ok
}

l28_leading_inline_code_keeps_link() {
    # A paragraph line that opens with an inline code span still has its
    # links checked: the blanked span must not read as indented code.
    local tasks; tasks=$(fresh_tasks l28)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_leading-code-span.md" <<EOF
---
description: leading inline code span control
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Leading code span

\`lint.py\` gains a check described in [the sibling](missing-after-code-span.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (link after leading code span blocks)" "$rc" "1" || ok=false
    assert_contains "link after leading code span reported" "$out" "missing-after-code-span.md" || ok=false
    $ok
}

l29_indented_list_content_keeps_links() {
    # Four-column-indented list content after a blank line is list
    # content, not an indented code block, so its links are checked.
    local tasks; tasks=$(fresh_tasks l29)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_indented-list-links.md" <<EOF
---
description: indented list content controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Indented list content

- Parent bullet

    - Nested bullet linking [nested](missing-nested-bullet.md).

1. First step.

    Continuation linking [continued](missing-continuation.md).
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (indented list links block)" "$rc" "1" || ok=false
    assert_contains "nested bullet link reported" "$out" "missing-nested-bullet.md" || ok=false
    assert_contains "continuation link reported" "$out" "missing-continuation.md" || ok=false
    $ok
}

l30_list_nested_fences_scrubbed() {
    # A fence sits zero to three columns right of its list item's content
    # column, so four-space-indented fences under `1.` are fences. Once the
    # list ends, a four-space-indented tilde line is no fence and its link
    # stays live.
    local tasks; tasks=$(fresh_tasks l30)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    cat > "$tasks/test_list-nested-fences.md" <<EOF
---
description: list-nested fence controls
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# List-nested fences

1. Tilde fence inside the list item:

    ~~~markdown
    See [tilde](missing-in-nested-tilde.md) for the citation form.
    ~~~

2. Backtick fence whose sample holds an unpaired backtick run:

    \`\`\`\`markdown
    Run \`\`\`make lint, then see [backtick](missing-in-nested-backtick.md).
    \`\`\`\`

    - Deeper item:

        ~~~
        [deep](missing-in-deep-fence.md)
        ~~~

After the list.

    ~~~
    [live](missing-after-list.md)
    ~~~
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (only the post-list link blocks)" "$rc" "1" || ok=false
    assert_eq "exactly one broken-link outside list fences" "$count" "1" || ok=false
    assert_contains "indented tilde after the list stays live" "$out" "missing-after-list.md" || ok=false
    assert_not_contains "nested tilde fence is ignored" "$out" "missing-in-nested-tilde.md" || ok=false
    assert_not_contains "nested backtick fence is ignored" "$out" "missing-in-nested-backtick.md" || ok=false
    assert_not_contains "fence in a deeper item is ignored" "$out" "missing-in-deep-fence.md" || ok=false
    $ok
}

l31_non_ascii_markdown_name_checked() {
    # git quotes non-ASCII paths unless -z is used; a non-ASCII markdown
    # file must stay in the git inventory and report its dangling link.
    local root; root=$(ext_tmp)
    git -C "$root" init -q
    mkdir -p "$root/tasks/archive" "$root/wiki"
    write_task "$root/tasks" "test_non-ascii.md" "2026-01-01T00:00:00"
    printf '# Overview\n\nSee [gone](missing-from-umlaut-page.md).\n' > "$root/wiki/übersicht.md"
    local ret; ret=$(run_lint "$root/tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (non-ASCII page link blocks)" "$rc" "1" || ok=false
    assert_contains "finding names the non-ASCII page" "$out" "wiki/übersicht.md" || ok=false
    assert_contains "dangling target reported" "$out" "missing-from-umlaut-page.md" || ok=false
    $ok
}

l32_subdirectory_root_uses_git_inventory() {
    # A tasks/ tree below the git toplevel still takes the git inventory,
    # so a gitignored node_modules under it stays silent while an
    # unignored dangling link under the same root still blocks.
    local top; top=$(ext_tmp)
    git -C "$top" init -q
    printf '%s\n' 'node_modules/' > "$top/.gitignore"
    local root="$top/packages/app"
    mkdir -p "$root/tasks/archive" "$root/node_modules/pkg" "$root/docs"
    write_task "$root/tasks" "test_subdir-walk.md" "2026-01-01T00:00:00"
    printf '# Vendored\n\nSee [docs](docs/api.md).\n' > "$root/node_modules/pkg/README.md"
    printf '# Guide\n\nSee [gone](missing-from-guide.md).\n' > "$root/docs/guide.md"
    local ret; ret=$(run_lint "$root/tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "broken-link" <<<"$out" || true)
    local ok=true
    assert_eq "exit 1 (unignored dangling link blocks)" "$rc" "1" || ok=false
    assert_eq "exactly one broken-link below the subdirectory root" "$count" "1" || ok=false
    assert_contains "unignored guide link reported" "$out" "missing-from-guide.md" || ok=false
    assert_not_contains "gitignored node_modules stays silent" "$out" "node_modules" || ok=false
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

# Status-gated body-prose checks: size and repeated-link fire only on live
# open, checked, and ready tasks, stay quiet on every archived page and on
# live implemented or audited tasks, and leave mechanical archive-inclusive
# findings untouched.
write_oversized_task() {
    local path=$1 status=$2 now=$3
    {
        cat <<EOF
---
description: oversized body-prose fixture
scope: "test"
created: $now
updated: $now
status: $status
reported-by: Test User
EOF
        if [[ "$status" == "finished" || "$status" == "deferred" || "$status" == "implemented" || "$status" == "audited" ]]; then
            printf 'implemented-by: Test User\n'
        fi
        cat <<EOF
---

# Oversized body
EOF
        local i
        for i in $(seq 1 320); do printf 'filler line %s\n' "$i"; done
    } > "$path"
}

write_twice_linker() {
    local path=$1 status=$2 now=$3 target=$4
    {
        cat <<EOF
---
description: twice-linking body-prose fixture
scope: "test"
created: $now
updated: $now
status: $status
reported-by: Test User
EOF
        if [[ "$status" == "finished" || "$status" == "deferred" || "$status" == "implemented" || "$status" == "audited" ]]; then
            printf 'implemented-by: Test User\n'
        fi
        cat <<EOF
---

# Twice linker

Context cites [t]($target) as background.
Approach edits [t]($target) again.
EOF
    } > "$path"
}

lo1_archived_body_prose_checks_stay_quiet() {
    local tasks; tasks=$(fresh_tasks lo1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    archived_task "$tasks" "link_target.md" "finished"
    write_oversized_task "$tasks/archive/big_oversized.md" "finished" "$now"
    write_twice_linker "$tasks/archive/twice_linker.md" "finished" "$now" "link_target.md"
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    local size_count rl_count
    size_count=$(grep -c "split into multiple tasks" <<<"$out" || true)
    rl_count=$(grep -c "repeated-link" <<<"$out" || true)
    assert_eq "exit 0 (archived body-prose warns are silent)" "$rc" "0" || ok=false
    assert_eq "no size finding on archived oversized page" "$size_count" "0" || ok=false
    assert_eq "no repeated-link finding on archived twice-linker" "$rl_count" "0" || ok=false
    $ok
}

lo2_live_body_prose_fixtures_still_warn() {
    local tasks; tasks=$(fresh_tasks lo2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "link_target.md" "$now"
    write_oversized_task "$tasks/big_oversized.md" "open" "$now"
    write_twice_linker "$tasks/twice_linker.md" "open" "$now" "link_target.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    local size_count rl_count
    size_count=$(grep -c "split into multiple tasks" <<<"$out" || true)
    rl_count=$(grep -c "repeated-link" <<<"$out" || true)
    assert_eq "exit 0 (live body-prose warns do not block)" "$rc" "0" || ok=false
    assert_eq "size finding on live oversized page" "$size_count" "1" || ok=false
    assert_eq "repeated-link finding on live twice-linker" "$rl_count" "1" || ok=false
    $ok
}

lo3_live_linking_archived_target_still_warns() {
    local tasks; tasks=$(fresh_tasks lo3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    archived_task "$tasks" "link_target.md" "finished"
    write_twice_linker "$tasks/live_archive-linker.md" "open" "$now" "archive/link_target.md"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    local count; count=$(grep -c "repeated-link" <<<"$out" || true)
    assert_eq "exit 0 (live repeated-link warn does not block)" "$rc" "0" || ok=false
    assert_eq "exactly one repeated-link finding" "$count" "1" || ok=false
    assert_contains "names the live linking page" "$out" "live_archive-linker" || ok=false
    $ok
}

lo4_archive_mode_still_reports_mechanical() {
    local tasks; tasks=$(fresh_tasks lo4)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/archive/defect_badstatus.md" <<EOF
---
description: archived page with a blocking defect
scope: "test"
created: $now
updated: $now
status: wip
reported-by: Test User
---

# Defect badstatus
EOF
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (mechanical archive defect still blocks)" "$rc" "1" || ok=false
    assert_contains "reports invalid status on archived page" "$out" "invalid status" || ok=false
    assert_contains "names the archived defect page" "$out" "defect_badstatus" || ok=false
    $ok
}

lo5_live_and_archive_inclusive_body_prose_match() {
    local tasks; tasks=$(fresh_tasks lo5)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "live_target.md" "$now"
    write_oversized_task "$tasks/live_big.md" "open" "$now"
    write_twice_linker "$tasks/live_twice.md" "open" "$now" "live_target.md"
    archived_task "$tasks" "arch_target.md" "finished"
    write_oversized_task "$tasks/archive/arch_big.md" "finished" "$now"
    write_twice_linker "$tasks/archive/arch_twice.md" "finished" "$now" "arch_target.md"
    local live_ret archive_ret
    live_ret=$(run_lint "$tasks")
    archive_ret=$(run_lint "$tasks" --include-archive)
    local live_out=${live_ret#*|} archive_out=${archive_ret#*|}
    local ok=true
    local live_size archive_size live_rl archive_rl
    live_size=$(grep -c "split into multiple tasks" <<<"$live_out" || true)
    archive_size=$(grep -c "split into multiple tasks" <<<"$archive_out" || true)
    live_rl=$(grep -c "repeated-link" <<<"$live_out" || true)
    archive_rl=$(grep -c "repeated-link" <<<"$archive_out" || true)
    assert_eq "size counts match across modes" "$live_size" "$archive_size" || ok=false
    assert_eq "repeated-link counts match across modes" "$live_rl" "$archive_rl" || ok=false
    assert_eq "one live size finding" "$live_size" "1" || ok=false
    assert_eq "one live repeated-link finding" "$live_rl" "1" || ok=false
    assert_not_contains "archive-inclusive size finding stays on live page" "$archive_out" "arch_big" || ok=false
    assert_not_contains "archive-inclusive repeated-link stays on live page" "$archive_out" "arch_twice" || ok=false
    $ok
}

# The size and repeated-link warnings prompt a reorganization before
# implementation, so they gate on status rather than on location: a live
# implemented or audited task stays quiet, while a live checked or ready
# task still warns. Under the earlier location gate every live page warned,
# so the quiet half of this scenario fails against that gate.
lo6_status_gate_quiets_completed_live_tasks() {
    local tasks; tasks=$(fresh_tasks lo6)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "link_target.md" "$now"
    local st
    for st in implemented audited checked ready; do
        write_oversized_task "$tasks/big_${st}.md" "$st" "$now"
        write_twice_linker "$tasks/twice_${st}.md" "$st" "$now" "link_target.md"
    done
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (status-gated warns do not block)" "$rc" "0" || ok=false
    # The filler lines also draw soft-pointer warns, which stay on every live
    # page, so each count reads only its own finding category.
    local size_n rl_n
    for st in implemented audited checked ready; do
        size_n=$(grep "split into multiple tasks" <<<"$out" | grep -c "big_${st}\.md" || true)
        rl_n=$(grep "repeated-link" <<<"$out" | grep -c "twice_${st}\.md" || true)
        case "$st" in
            implemented|audited)
                assert_eq "no size finding on a live $st page" "$size_n" "0" || ok=false
                assert_eq "no repeated-link finding on a live $st page" "$rl_n" "0" || ok=false
                ;;
            *)
                assert_eq "one size finding on a live $st page" "$size_n" "1" || ok=false
                assert_eq "one repeated-link finding on a live $st page" "$rl_n" "1" || ok=false
                ;;
        esac
    done
    $ok
}

# An archived page that still carries open, checked, or ready has one actual
# error: a status other than finished or deferred under archive/, which the
# blocking migration finding reports. The size and repeated-link warnings stay
# quiet there, because an archived body stays as delivered whatever status it
# carries. A status-only gate fired both warnings on such a page, so the quiet
# half of this scenario fails against that gate.
lo7_archived_live_status_reports_only_migration() {
    local tasks; tasks=$(fresh_tasks lo7)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    archived_task "$tasks" "link_target.md" "finished"
    local st
    for st in open checked ready; do
        write_oversized_task "$tasks/archive/big_${st}.md" "$st" "$now"
        write_twice_linker "$tasks/archive/twice_${st}.md" "$st" "$now" "link_target.md"
    done
    local ret; ret=$(run_lint "$tasks" --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (the archived live status blocks)" "$rc" "1" || ok=false
    local page migration_n size_n rl_n
    for st in open checked ready; do
        for page in "big_${st}" "twice_${st}"; do
            migration_n=$(grep "migrate to \`status: finished\`" <<<"$out" | grep -c "archive/${page}\.md" || true)
            assert_eq "one migration finding on archived $page" "$migration_n" "1" || ok=false
        done
        size_n=$(grep "split into multiple tasks" <<<"$out" | grep -c "big_${st}\.md" || true)
        rl_n=$(grep "repeated-link" <<<"$out" | grep -c "twice_${st}\.md" || true)
        assert_eq "no size finding on an archived $st page" "$size_n" "0" || ok=false
        assert_eq "no repeated-link finding on an archived $st page" "$rl_n" "0" || ok=false
    done
    # The close-out verifies a just-moved file through --file, so the scoped
    # run reports the same actual error and stays quiet the same way.
    ret=$(run_lint "$tasks" --file "archive/twice_ready.md")
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (file-scoped run blocks on the archived live status)" "$rc" "1" || ok=false
    assert_contains "file-scoped run reports the migration finding" "$out" "migrate to \`status: finished\`" || ok=false
    assert_not_contains "file-scoped run reports no repeated-link finding" "$out" "repeated-link" || ok=false
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
# File-scoped mode (--file): close-out verifies exactly the one moved file.
# stage_scoped_tree lays down three archived pages (an oversized one, one
# that links a local target twice, one carrying a blocking frontmatter
# defect) plus the clean link target, so a scoped run's "reports only the
# named file" contract can be asserted against real neighbours.
###############################################################################

# archived_task <tasks> <filename> <status> -> writes a finished/deferred
# archive fixture carrying the provenance that status needs.
archived_task() {
    local tasks=$1 filename=$2 status=$3 now
    now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/archive/$filename" <<EOF
---
description: archived $status fixture
scope: "test"
created: $now
updated: $now
status: $status
reported-by: Test User
implemented-by: Test User
---

# Archived $filename
EOF
}

stage_scoped_tree() {
    local tasks=$1 now
    now=$(date +%Y-%m-%dT%H:%M:%S)
    archived_task "$tasks" "link_target.md" "finished"
    # Oversized archived page: header plus >300 filler lines.
    {
        cat <<EOF
---
description: oversized archived fixture
scope: "test"
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Big oversized
EOF
        local i
        for i in $(seq 1 320); do printf 'filler line %s\n' "$i"; done
    } > "$tasks/archive/big_oversized.md"
    # Archived page linking one existing local target twice.
    emit "$tasks/archive/twice_linker.md" <<EOF
---
description: archived page linking one target twice
scope: "test"
created: $now
updated: $now
status: finished
reported-by: Test User
implemented-by: Test User
---

# Twice linker

Context cites [t](link_target.md) as background.
Approach edits [t](link_target.md) again.
EOF
    # Archived page carrying a blocking frontmatter defect (invalid status).
    emit "$tasks/archive/defect_badstatus.md" <<EOF
---
description: archived page with a blocking defect
scope: "test"
created: $now
updated: $now
status: wip
reported-by: Test User
---

# Defect badstatus
EOF
}

fs1_scoped_archived_page_reports_only_itself() {
    local tasks; tasks=$(fresh_tasks fs1)
    stage_scoped_tree "$tasks"
    local ok=true

    # Scope to the mechanical defect: its own blocking finding, neither
    # body-prose neighbour named.
    local ret; ret=$(run_lint "$tasks" --file tasks/archive/defect_badstatus.md)
    local rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (scoped blocking defect)" "$rc" "1" || ok=false
    assert_contains "reports the scoped page's invalid status" "$out" "invalid status" || ok=false
    assert_not_contains "does not name the oversized page" "$out" "big_oversized" || ok=false
    assert_not_contains "does not name the twice-linking page" "$out" "twice_linker" || ok=false

    # Scope to the oversized page: body-prose size check is live-only.
    ret=$(run_lint "$tasks" --file tasks/archive/big_oversized.md)
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 0 (archived oversized page is quiet)" "$rc" "0" || ok=false
    assert_not_contains "no size warn on archived oversized page" "$out" "split into multiple tasks" || ok=false
    assert_not_contains "does not name the twice-linking page" "$out" "twice_linker" || ok=false
    assert_not_contains "does not name the defect page" "$out" "defect_badstatus" || ok=false

    # Scope to the twice-linking page: body-prose repeated-link check is live-only.
    ret=$(run_lint "$tasks" --file archive/twice_linker.md)
    rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "repeated-link" <<<"$out" || true)
    assert_eq "exit 0 (archived twice-linker is quiet)" "$rc" "0" || ok=false
    assert_eq "no repeated-link finding on archived page" "$count" "0" || ok=false
    assert_not_contains "does not name the oversized page" "$out" "big_oversized" || ok=false
    assert_not_contains "does not name the defect page" "$out" "defect_badstatus" || ok=false
    $ok
}

fs2_scoped_live_page_excludes_all_others() {
    local tasks; tasks=$(fresh_tasks fs2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    # Live page under test carries its own (live-only) soft-pointer warn.
    emit "$tasks/live_target.md" <<EOF
---
description: live page with its own soft-pointer warn
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Live target

The guard sits in \`deployment.sh:242\` and must stay put.
EOF
    # A second live page and an archived blocking defect must not surface.
    write_task "$tasks" "live_sibling.md" "$now"
    archived_task_defect() {
        emit "$tasks/archive/defect_badstatus.md" <<EOF
---
description: archived page with a blocking defect
scope: "test"
created: $now
updated: $now
status: wip
reported-by: Test User
---

# Defect badstatus
EOF
    }
    archived_task_defect
    local ret; ret=$(run_lint "$tasks" --file live_target.md)
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (only the scoped live page's warn counts)" "$rc" "0" || ok=false
    assert_contains "reports the scoped page's soft-pointer warn" "$out" "soft-pointer" || ok=false
    assert_not_contains "does not name the live sibling" "$out" "live_sibling" || ok=false
    assert_not_contains "does not name the archived defect" "$out" "defect_badstatus" || ok=false
    $ok
}

fs3_invalid_path_exits_nonzero() {
    local tasks; tasks=$(fresh_tasks fs3)
    local root; root=$(dirname "$tasks")
    write_task "$tasks" "test_present.md" "$(date +%Y-%m-%dT%H:%M:%S)"
    # A real file sitting beside tasks/, inside the project root but
    # outside the tasks tree, so it resolves-outside rather than missing.
    : > "$root/outside.md"
    local ok=true

    local ret; ret=$(run_lint "$tasks" --file tasks/archive/nope.md)
    local rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (named file does not exist)" "$rc" "1" || ok=false
    assert_contains "names the missing path" "$out" "tasks/archive/nope.md" || ok=false

    ret=$(run_lint "$tasks" --file "$root/outside.md")
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (named file resolves outside the tasks root)" "$rc" "1" || ok=false
    assert_contains "names the offending path" "$out" "outside.md" || ok=false
    assert_contains "explains the out-of-root cause" "$out" "outside the tasks root" || ok=false
    $ok
}

fs4_conflicting_flags_and_file_only() {
    local tasks; tasks=$(fresh_tasks fs4)
    write_task "$tasks" "test_present.md" "$(date +%Y-%m-%dT%H:%M:%S)"
    local ok=true

    # --file with --include-archive is rejected at argparse, naming both.
    local ret; ret=$(run_lint "$tasks" --file tasks/test_present.md --include-archive)
    local rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 2 (mutually exclusive flags)" "$rc" "2" || ok=false
    assert_contains "names the conflicting flags" "$out" "not allowed with argument" || ok=false
    assert_contains "names --include-archive" "$out" "--include-archive" || ok=false

    # --file alone scopes without requiring --include-archive.
    ret=$(run_lint "$tasks" --file tasks/test_present.md)
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 0 (--file only, no --include-archive needed)" "$rc" "0" || ok=false
    assert_contains "reports a clean scoped run" "$out" "clean — no issues" || ok=false
    $ok
}

fs5_scoped_duplicate_basename_reports_named_only() {
    local tasks; tasks=$(fresh_tasks fs5)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "dup_page.md" "$now"
    archived_task "$tasks" "dup_page.md" "finished"
    local ret; ret=$(run_lint "$tasks" --file tasks/dup_page.md)
    local rc=${ret%%|*} out=${ret#*|}
    local count; count=$(grep -c "collision" <<<"$out")
    local ok=true
    assert_eq "exit 1 (named file collides)" "$rc" "1" || ok=false
    assert_eq "exactly one collision finding (named file only)" "$count" "1" || ok=false
    assert_contains "reports the duplicate filename" "$out" "duplicate task filename" || ok=false
    $ok
}

fs6_help_and_usage_document_file_option() {
    local ok=true
    # --help names the file-scoped option.
    local help; help=$(python3 "$LINT" --help 2>&1)
    assert_contains "--help documents --file" "$help" "--file" || ok=false
    # The module-docstring Usage: CLI list names the option beside the others.
    local usage; usage=$(grep -F "python3 lint.py [TASKS_PATH]" "$LINT")
    assert_contains "Usage line names --file" "$usage" "--file" || ok=false
    assert_contains "Usage line still names --include-archive" "$usage" "--include-archive" || ok=false
    $ok
}

fs7_scoped_path_edge_cases() {
    local tasks; tasks=$(fresh_tasks fs7)
    local root; root=$(dirname "$tasks")
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    write_task "$tasks" "test_present.md" "$now"
    # A decoy project whose tasks tree carries the same relative path, so a
    # run started from inside it must still lint the tasks root it was given.
    mkdir -p "$root/decoy/tasks/archive"
    archived_task "$root/decoy/tasks" "test_moved.md" "finished"
    archived_task "$tasks" "test_moved.md" "finished"
    local ok=true

    # An empty --file value is rejected instead of silently linting the tree.
    local ret; ret=$(run_lint "$tasks" --file "")
    local rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (empty --file value)" "$rc" "1" || ok=false
    assert_contains "explains the empty value" "$out" "value given is empty" || ok=false
    assert_not_contains "lints no other page" "$out" "test_present" || ok=false

    # The named tasks root outranks an identically named file under CWD.
    ret=$(run_lint_in "$root/decoy" "$tasks" --file tasks/archive/test_moved.md)
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 0 (named tasks root wins over the CWD decoy)" "$rc" "0" || ok=false
    assert_contains "audits the named tasks root" "$out" "$tasks" || ok=false
    assert_not_contains "audits no decoy tree" "$out" "decoy" || ok=false

    # A directory argument is named as such rather than as a missing file.
    ret=$(run_lint "$tasks" --file archive)
    rc=${ret%%|*} out=${ret#*|}
    assert_eq "exit 1 (directory argument)" "$rc" "1" || ok=false
    assert_contains "names the directory cause" "$out" "is a directory" || ok=false
    $ok
}

###############################################################################
# lint.py — unquoted values YAML would misread, and quoted readings.
###############################################################################

y1_unquoted_colon_space_blocks() {
    local tasks; tasks=$(fresh_tasks y1)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_colon.md" <<EOF
---
description: Turn make install into environment preparation: declare the runtime
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Colon in description
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (colon followed by a space)" "$rc" "1" || ok=false
    assert_contains "frontmatter category" "$out" "frontmatter" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y2_unquoted_hash_after_whitespace_blocks() {
    local tasks; tasks=$(fresh_tasks y2)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_hash.md" <<EOF
---
description: keep the prefix # drop the suffix
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Hash in description
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (# after whitespace)" "$rc" "1" || ok=false
    assert_contains "frontmatter category" "$out" "frontmatter" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y3_unquoted_backtick_start_blocks() {
    local tasks; tasks=$(fresh_tasks y3)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_tick.md" <<EOF
---
description: \`make lint\` runs the checks
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Backtick description
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with a backtick)" "$rc" "1" || ok=false
    assert_contains "frontmatter category" "$out" "frontmatter" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y4_unquoted_ending_colon_blocks() {
    local tasks; tasks=$(fresh_tasks y4)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_endcolon.md" <<EOF
---
description: environment preparation:
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Trailing colon
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value ends with a colon)" "$rc" "1" || ok=false
    assert_contains "frontmatter category" "$out" "frontmatter" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y5_quoted_colon_and_hash_is_clean() {
    local tasks; tasks=$(fresh_tasks y5)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_quoted.md" <<EOF
---
description: "preparation: declare the runtime # keep the hash"
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Quoted colon and hash
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (quoted colon and hash)" "$rc" "0" || ok=false
    assert_not_contains "no misread finding" "$out" "unquoted value for" || ok=false
    $ok
}

y6_quoted_hash_keeps_full_description_length() {
    local tasks; tasks=$(fresh_tasks y6)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local inner
    inner=$(python3 -c 'print("# " + ("x" * 199))')
    emit "$tasks/test_longhash.md" <<EOF
---
description: "$inner"
scope: "test"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Long quoted description

The hash near the start stays inside the value.
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (length warning is not blocking)" "$rc" "0" || ok=false
    assert_contains "length uses the whole quoted value" "$out" "description is 201 chars" || ok=false
    assert_not_contains "no misread finding" "$out" "unquoted value for" || ok=false
    $ok
}

y7_quoted_scope_hash_is_text() {
    local tasks; tasks=$(fresh_tasks y7)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local page="$tasks/test_scopehash.md"
    emit "$page" <<EOF
---
description: valid task harness fixture
scope: "label # with a hash"
created: $now
updated: $now
status: open
reported-by: Test User
---

# Quoted scope label
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local got
    got=$(python3 -c '
import importlib.util
import pathlib
import sys
spec = importlib.util.spec_from_file_location("task_lint", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
print(mod.get_raw_scope(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")))
' "$LINT" "$page")
    local ok=true
    assert_eq "exit 0 (quoted scope is text)" "$rc" "0" || ok=false
    assert_not_contains "scope check does not treat it as a path" "$out" "scope path" || ok=false
    assert_eq "get_raw_scope returns the quoted label whole" "$got" '"label # with a hash"' || ok=false
    $ok
}

# description is the literal scalar text, including a leading marker.
y_lint_description() {
    local id=$1 description=$2
    local tasks; tasks=$(fresh_tasks "$id")
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    python3 -c '
import sys
from pathlib import Path
tasks = Path(sys.argv[1])
description = sys.argv[2]
now = sys.argv[3]
text = (
    "---\n"
    "description: " + description + "\n"
    "scope: \"test\"\n"
    "created: " + now + "\n"
    "updated: " + now + "\n"
    "status: open\n"
    "reported-by: Test User\n"
    "---\n"
    "\n"
    "# Hostile description\n"
)
(tasks / "test_hostile.md").write_text(text, encoding="utf-8")
' "$tasks" "$description" "$now" || return 1
    run_lint "$tasks"
}

y8_unquoted_flow_open_blocks() {
    local ret; ret=$(y_lint_description y8 "{braces} lead the summary")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with {)" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    assert_contains "prescribes quoting" "$out" "wrap it in double quotes" || ok=false
    $ok
}

y9_unquoted_flow_close_blocks() {
    local ret; ret=$(y_lint_description y9 "}braces lead")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with })" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y10_unquoted_flow_comma_blocks() {
    local ret; ret=$(y_lint_description y10 ",comma lead")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with ,)" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y11_unquoted_leading_dash_blocks() {
    local ret; ret=$(y_lint_description y11 "- a leading dash")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with dash space)" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y12_unquoted_leading_question_blocks() {
    local ret; ret=$(y_lint_description y12 "? explicit key")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (value starts with question space)" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y13_unquoted_colon_tab_blocks() {
    local ret; ret=$(y_lint_description y13 $'key:\tvalue here')
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (colon followed by a tab)" "$rc" "1" || ok=false
    assert_contains "names the description key" "$out" "unquoted value for description" || ok=false
    $ok
}

y14_status_trailing_comment_asks_to_remove_it() {
    local tasks; tasks=$(fresh_tasks y14)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_status_comment.md" <<EOF
---
description: valid task harness fixture
scope: "test"
created: $now
updated: $now
status: open # waiting on review
reported-by: Test User
---

# Status comment
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (trailing comment on status)" "$rc" "1" || ok=false
    assert_contains "names the status key" "$out" "unquoted value for status has a trailing comment" || ok=false
    assert_contains "prescribes removing the comment" "$out" "remove the comment and leave the value" || ok=false
    assert_not_contains "quoting is not the status repair" "$out" "wrap it in double quotes" || ok=false
    assert_not_contains "status stays a known value" "$out" "invalid status" || ok=false
    $ok
}

y15_scope_trailing_comment_stays_a_path() {
    local tasks; tasks=$(fresh_tasks y15)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    emit "$tasks/test_scope_comment.md" <<EOF
---
description: valid task harness fixture
scope: tasks/archive # kept as a path
created: $now
updated: $now
status: open
reported-by: Test User
---

# Scope comment
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 1 (trailing comment on a path scope)" "$rc" "1" || ok=false
    assert_contains "names the scope key" "$out" "unquoted value for scope has a trailing comment" || ok=false
    assert_contains "prescribes removing the comment" "$out" "remove the comment and leave the value" || ok=false
    assert_not_contains "quoting would turn the path into a label" "$out" "wrap it in double quotes" || ok=false
    assert_not_contains "the path under the comment still resolves" "$out" "does not exist" || ok=false
    $ok
}

y16_double_quoted_escapes_decode() {
    local tasks; tasks=$(fresh_tasks y16)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local page="$tasks/test_escapes.md"
    NOW="$now" python3 -c '
import os
from pathlib import Path
import sys
page = Path(sys.argv[1])
now = os.environ["NOW"]
text = (
    "---\n"
    "description: \"say \\\"hi\\\"\"\n"
    "scope: \"test\"\n"
    f"created: {now}\n"
    f"updated: {now}\n"
    "status: open\n"
    "reported-by: Test User\n"
    "---\n"
    "\n"
    "# Escapes\n"
)
page.write_text(text, encoding="utf-8")
' "$page"
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local got
    got=$(python3 -c '
import importlib.util
import pathlib
import sys
spec = importlib.util.spec_from_file_location("task_lint", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
print(mod.parse_frontmatter(text)[0]["description"])
print(mod._decode_quoted_scalar("\"a\\\\b\""))
' "$LINT" "$page")
    local ok=true
    assert_eq "exit 0 (escaped quotes are valid)" "$rc" "0" || ok=false
    assert_eq "description reads the escaped quotes" "$got" $'say "hi"\na\\b' || ok=false
    $ok
}

y17_apostrophe_does_not_keep_a_later_comment() {
    local tasks; tasks=$(fresh_tasks y17)
    local now; now=$(date +%Y-%m-%dT%H:%M:%S)
    local page="$tasks/test_apostrophe.md"
    emit "$page" <<EOF
---
description: valid task harness fixture
scope: "test"
created: $now
updated: $now
status: open
reported-by: O'Brien # author
---

# Apostrophe
EOF
    local ret; ret=$(run_lint "$tasks")
    local rc=${ret%%|*} out=${ret#*|}
    local got
    got=$(python3 -c '
import importlib.util
import pathlib
import sys
spec = importlib.util.spec_from_file_location("task_lint", sys.argv[1])
mod = importlib.util.module_from_spec(spec)
sys.modules[spec.name] = mod
spec.loader.exec_module(mod)
text = pathlib.Path(sys.argv[2]).read_text(encoding="utf-8")
print(mod.parse_frontmatter(text)[0]["reported-by"])
' "$LINT" "$page")
    local ok=true
    assert_eq "exit 1 (hash after the name is still a misread)" "$rc" "1" || ok=false
    assert_contains "quotes the provenance value" "$out" "unquoted value for reported-by" || ok=false
    assert_contains "prescribes quoting" "$out" "wrap it in double quotes" || ok=false
    assert_eq "parsed name drops the comment" "$got" "O'Brien" || ok=false
    $ok
}

y18_plain_scalars_yaml_accepts_stay_clean() {
    local ret; ret=$(y_lint_description y18 "-a no space, ?x no space, ratio 1:1")
    local rc=${ret%%|*} out=${ret#*|}
    local ok=true
    assert_eq "exit 0 (plain scalars YAML accepts)" "$rc" "0" || ok=false
    assert_not_contains "no misread finding" "$out" "unquoted value for" || ok=false
    $ok
}

###############################################################################
# Run scenarios
###############################################################################

scenario l1 "lint: project-root-relative body link resolves"   l1_project_root_fallback_resolves
scenario l2 "lint: link missing under both roots blocks"       l2_missing_under_both_roots_blocks
scenario l3 "lint: sibling-task link still resolves"           l3_sibling_task_link_resolves
scenario l4 "lint: wiki dangling task link blocks on default"  l4_wiki_dangling_task_link_blocks
scenario l5 "lint: non-task md skips non-link per-file checks" l5_non_task_md_skips_other_checks
scenario l6 "lint: non-.md target existence check"             l6_non_md_target_existence
scenario l7 "lint: outbound and outside-repo targets silent"   l7_outbound_targets_silent
scenario l8 "lint: directory target resolves"                  l8_directory_target_resolves
scenario l9 "lint: Makefile EXCLUDE prunes dangling tree"      l9_makefile_exclude_prunes_dangling
scenario l10 "lint: no EXCLUDE reports dangling outside .git"  l10_no_exclude_reports_dangling
scenario l11 "lint: --file scopes link checks to named task"   l11_file_scope_ignores_other_md
scenario l12 "lint: fenced markdown link ignored"              l12_fenced_link_ignored
scenario l13 "lint: inline-code markdown link ignored"         l13_inline_code_link_ignored
scenario l14 "lint: empty labels resolve existing and missing" l14_empty_labels_existing_and_missing
scenario l15 "lint: nested labels resolve existing and missing" l15_nested_labels_existing_and_missing
scenario l16 "lint: angle destinations retain spaces"          l16_angle_destinations_existing_and_missing
scenario l17 "lint: balanced-parenthesis destinations parse"   l17_balanced_destinations_existing_and_missing
scenario l18 "lint: reference links resolve definitions"       l18_reference_links_existing_and_missing
scenario l19 "lint: references, escapes, images, and entities" l19_reference_syntax_escapes_and_entities
scenario l20 "lint: nested image descriptions stay excluded"  l20_nested_image_descriptions_are_excluded
scenario l21 "lint: reference title lines stay excluded"       l21_reference_definition_title_lines_are_excluded
scenario l22 "lint: URL-spelled destinations normalize"        l22_url_spelled_destinations_normalize
scenario l23 "lint: autolink and raw HTML ignored"             l23_literal_raw_constructs_ignored
scenario l24 "lint: gitignored node_modules stay silent"       l24_gitignore_skips_node_modules
scenario l25 "lint: non-prune EXCLUDE keeps link check"        l25_non_prune_exclude_keeps_check
scenario l26 "lint: leading-slash is repo-root-relative"       l26_leading_slash_repo_root_relative
scenario l27 "lint: EXCLUDE with find actions is rejected"     l27_exclude_with_find_action_rejected
scenario l28 "lint: leading inline code keeps line links"      l28_leading_inline_code_keeps_link
scenario l29 "lint: indented list content keeps links"         l29_indented_list_content_keeps_links
scenario l30 "lint: list-nested fences are scrubbed"           l30_list_nested_fences_scrubbed
scenario l31 "lint: non-ASCII markdown name stays checked"     l31_non_ascii_markdown_name_checked
scenario l32 "lint: subdirectory root uses git inventory"      l32_subdirectory_root_uses_git_inventory

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
scenario lo1 "lint: archived body-prose checks stay quiet"     lo1_archived_body_prose_checks_stay_quiet
scenario lo2 "lint: live body-prose fixtures still warn"       lo2_live_body_prose_fixtures_still_warn
scenario lo3 "lint: live page linking archive still warns"     lo3_live_linking_archived_target_still_warns
scenario lo4 "lint: archive mode still reports mechanical"     lo4_archive_mode_still_reports_mechanical
scenario lo5 "lint: live and archive-inclusive body-prose match" lo5_live_and_archive_inclusive_body_prose_match
scenario lo6 "lint: status gate quiets completed live tasks"   lo6_status_gate_quiets_completed_live_tasks
scenario lo7 "lint: archived live status reports only migration" lo7_archived_live_status_reports_only_migration
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

scenario y1  "lint: unquoted colon-space blocks"            y1_unquoted_colon_space_blocks
scenario y2  "lint: unquoted hash after whitespace blocks"  y2_unquoted_hash_after_whitespace_blocks
scenario y3  "lint: unquoted backtick start blocks"         y3_unquoted_backtick_start_blocks
scenario y4  "lint: unquoted value ending in colon blocks"  y4_unquoted_ending_colon_blocks
scenario y5  "lint: quoted colon and hash is clean"         y5_quoted_colon_and_hash_is_clean
scenario y6  "lint: quoted hash keeps description length"   y6_quoted_hash_keeps_full_description_length
scenario y7  "lint: quoted scope hash is text"              y7_quoted_scope_hash_is_text
scenario y8  "lint: unquoted value starting with { blocks" y8_unquoted_flow_open_blocks
scenario y9  "lint: unquoted value starting with } blocks" y9_unquoted_flow_close_blocks
scenario y10 "lint: unquoted value starting with , blocks" y10_unquoted_flow_comma_blocks
scenario y11 "lint: unquoted leading dash-space blocks"    y11_unquoted_leading_dash_blocks
scenario y12 "lint: unquoted leading question-space blocks" y12_unquoted_leading_question_blocks
scenario y13 "lint: unquoted colon followed by tab blocks" y13_unquoted_colon_tab_blocks
scenario y14 "lint: status trailing comment is removed"    y14_status_trailing_comment_asks_to_remove_it
scenario y15 "lint: scope trailing comment stays a path"   y15_scope_trailing_comment_stays_a_path
scenario y16 "lint: double-quoted escapes decode"          y16_double_quoted_escapes_decode
scenario y17 "lint: apostrophe does not keep a comment"    y17_apostrophe_does_not_keep_a_later_comment
scenario y18 "lint: plain scalars YAML accepts stay clean" y18_plain_scalars_yaml_accepts_stay_clean

scenario de1 "lint: absent design-extended is clean"           de1_absent_design_extended_is_clean
scenario de2 "lint: non-boolean design-extended blocks"        de2_non_boolean_design_extended_blocks
scenario de3 "lint: boolean design-extended is clean"          de3_boolean_design_extended_is_clean

scenario am1 "archive: tracked move records a rename"          am1_tracked_move_records_a_rename
scenario am2 "archive: untracked move takes the fallback"      am2_untracked_move_takes_the_fallback
scenario am3 "archive: one probe covers a missing repository"  am3_probe_fails_outside_a_repository

scenario fs1 "lint: --file scopes an archived page to itself"  fs1_scoped_archived_page_reports_only_itself
scenario fs2 "lint: --file scopes a live page, excludes others" fs2_scoped_live_page_excludes_all_others
scenario fs3 "lint: --file invalid path exits non-zero"        fs3_invalid_path_exits_nonzero
scenario fs4 "lint: --file conflicts with --include-archive"   fs4_conflicting_flags_and_file_only
scenario fs5 "lint: --file duplicate basename reports named only" fs5_scoped_duplicate_basename_reports_named_only
scenario fs6 "lint: --help and Usage document --file"          fs6_help_and_usage_document_file_option
scenario fs7 "lint: --file edge cases (empty, CWD decoy, dir)"  fs7_scoped_path_edge_cases

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
