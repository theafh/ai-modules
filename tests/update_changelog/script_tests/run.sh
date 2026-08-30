#!/usr/bin/env bash
# Local-only deterministic checks for the update_changelog skill.
#
# Scope: the prompt text that defines incremental day selection, plus the
# bundled prepare_changelog_day.sh script that supplies a full day's committed
# history to the model through a durable context-file handoff. The agent-level
# summarization step remains a skill behavior concern, not a shell-unit concern.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SKILL_FILE="$REPO_ROOT/plugins/ai_dev/skills/update_changelog/SKILL.md"
PREPARE="$REPO_ROOT/plugins/ai_dev/skills/update_changelog/scripts/prepare_changelog_day.sh"

SCRATCH="$SCRIPT_DIR/scratch"
RESULTS="$SCRIPT_DIR/../results/script_tests.log"

PASS=0
FAIL=0
FAILED_IDS=()

mkdir -p "$SCRATCH"
mkdir -p "$(dirname "$RESULTS")"
: > "$RESULTS"

log() { printf '%s\n' "$*" | tee -a "$RESULTS" >&2; }

fresh_repo() {
    local id=$1
    local repo="$SCRATCH/$id/repo"
    rm -rf "${SCRATCH:?}/$id"
    mkdir -p "$repo"
    (
        cd "$repo"
        git init --quiet --initial-branch=main
        git config user.email "harness@example.com"
        git config user.name "Harness"
    ) || return 1
    printf '%s' "$repo"
}

commit_file() {
    local repo=$1 date=$2 path=$3 content=$4 subject=$5
    mkdir -p "$(dirname "$repo/$path")"
    printf '%s\n' "$content" > "$repo/$path"
    (
        cd "$repo" || exit 1
        git add "$path"
        GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git commit --quiet -m "$subject"
    )
}

write_changelog_with_newest_day() {
    local repo=$1 day=$2
    cat > "$repo/CHANGELOG.md" <<EOF
# CHANGELOG — Harness

Entries are grouped strictly by day, kept on their original implementation dates, and immutable once written.

## ${day} — Existing Work

- **added:** Existing entry already recorded.
- **Files changed:** \`feature.txt\`

---
EOF
}

documented_dates() {
    local repo=$1
    local last_day=""
    if [[ -f "$repo/CHANGELOG.md" ]]; then
        last_day="$(awk '/^## [0-9]{4}-[0-9]{2}-[0-9]{2}/ { print $2; exit }' "$repo/CHANGELOG.md")"
    fi

    if [[ -n "$last_day" ]]; then
        (
            cd "$repo" || exit 1
            git --no-pager log --reverse --format='%ad' --date=short --no-merges --since="${last_day}T00:00:00" | sort -u
        )
    else
        (
            cd "$repo" || exit 1
            git --no-pager log --reverse --format='%ad' --date=short --no-merges | sort -u
        )
    fi
}

run_prepare() {
    local repo=$1 date=$2
    local out rc
    out=$(cd "$repo" && "$PREPARE" "$date" 2>&1) && rc=0 || rc=$?
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

assert_not_contains() {
    local label=$1 haystack=$2 needle=$3
    if [[ "$haystack" != *"$needle"* ]]; then
        return 0
    fi
    log "    [unwanted substring present: $label]"
    log "      needle:   $(printf '%q' "$needle")"
    return 1
}

assert_file_readable() {
    local label=$1 path=$2
    if [[ -r "$path" ]]; then
        return 0
    fi
    log "    [file not readable: $label]"
    log "      path:     $(printf '%q' "$path")"
    return 1
}

assert_abs_path() {
    local label=$1 path=$2
    if [[ "$path" == /* ]]; then
        return 0
    fi
    log "    [not absolute path: $label]"
    log "      path:     $(printf '%q' "$path")"
    return 1
}

assert_line_count() {
    local label=$1 text=$2 expected=$3
    local actual
    actual="$(printf '%s\n' "$text" | wc -l | tr -d ' ')"
    assert_eq "$label" "$actual" "$expected"
}

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

s1_skill_text_carries_boundary_rules() {
    local text
    text="$(cat "$SKILL_FILE")"
    local ok=true
    assert_contains "run scope tag" "$text" "<run_scope>" || ok=false
    assert_contains "committed scope" "$text" "committed git history only" || ok=false
    assert_contains "same-day reason" "$text" "same-day commits can land after its section was written" || ok=false
    assert_contains "last day query" "$text" "--since={D}T00:00:00" || ok=false
    assert_contains "reconciliation tag" "$text" "<last_recorded_day_reconciliation>" || ok=false
    assert_contains "preserve existing entry text" "$text" "Keep every existing entry's date, category, and text unchanged" || ok=false
    assert_contains "consume context tag" "$text" "<consume_context>" || ok=false
    assert_contains "full read protocol" "$text" "<full_read>" || ok=false
    assert_contains "paginated read protocol" "$text" "<paginated_read>" || ok=false
    assert_contains "ordered slicing fallback" "$text" "<ordered_slicing_fallback>" || ok=false
    assert_contains "hard rule blocks git log" "$text" "Never re-derive the day with \`git log\`, \`git diff\`, or \`git status\`" || ok=false
    assert_contains "hard rule blocks head" "$text" "never truncate the blob with \`head\`" || ok=false
    assert_contains "tool description uses context file" "$text" "stdout prints exactly two lines: the context file's absolute path" || ok=false
    assert_contains "procedure uses returned context file" "$text" "Read the returned context file according to \`<consume_context>\`" || ok=false
    assert_not_contains "stale drop instruction" "$text" "drop dates already covered" || ok=false
    assert_not_contains "consume protocol does not cite sibling" "$text" "git_commit" || ok=false
    $ok
}

s2_same_day_incremental_reopens_last_day_with_file_handoff() {
    local repo
    repo="$(fresh_repo same-day)" || return 1
    commit_file "$repo" "2026-06-10T09:00:00 +0000" "feature.txt" "first" "add first same-day change" || return 1
    write_changelog_with_newest_day "$repo" "2026-06-10"
    commit_file "$repo" "2026-06-10T17:30:00 +0000" "later.txt" "later" "add later same-day change" || return 1
    printf 'draft\n' > "$repo/draft.txt"

    local dates ret rc out ctx_path directive context ok=true
    dates="$(documented_dates "$repo")"
    assert_eq "incremental dates include last recorded day" "$dates" "2026-06-10" || ok=false

    ret="$(run_prepare "$repo" "2026-06-10")"
    rc=${ret%%|*}
    out=${ret#*|}
    assert_eq "prepare exit" "$rc" "0" || ok=false
    assert_line_count "prepare stdout has path plus directive only" "$out" "2" || ok=false
    assert_not_contains "stdout omits context blob" "$out" "<changelog_day>" || ok=false

    ctx_path="$(printf '%s\n' "$out" | sed -n '1p')"
    directive="$(printf '%s\n' "$out" | sed -n '2p')"
    assert_abs_path "context path is absolute" "$ctx_path" || ok=false
    assert_contains "stdout directive names full read" "$directive" "Read this entire file" || ok=false
    assert_contains "stdout directive blocks re-derivation" "$directive" "Do NOT re-run git log, git diff, or git status" || ok=false
    assert_contains "stdout directive blocks head truncation" "$directive" "do NOT pipe the blob through head" || ok=false
    assert_file_readable "context file remains after script exit" "$ctx_path" || ok=false

    if [[ -r "$ctx_path" ]]; then
        context="$(cat "$ctx_path")"
        rm -f "$ctx_path"
    else
        context=""
    fi

    assert_contains "context root tag" "$context" "<changelog_day>" || ok=false
    assert_contains "context commits section" "$context" "<commits>" || ok=false
    assert_contains "context files section" "$context" "<files_changed>" || ok=false
    assert_contains "context diffs section" "$context" "<diffs>" || ok=false
    assert_contains "context entry instruction" "$context" "<entry_instruction>" || ok=false
    assert_contains "later same-day commit subject" "$context" "<subject>add later same-day change</subject>" || ok=false
    assert_contains "later same-day file" "$context" "later.txt" || ok=false
    assert_not_contains "uncommitted working tree ignored" "$context" "draft.txt" || ok=false
    assert_contains "immutable entry format" "$context" 'format "- **Category:** Plain-English summary."' || ok=false
    assert_not_contains "no status marker slot" "$context" "[status]" || ok=false
    assert_not_contains "no current-state status assignment" "$context" "Assign status markers" || ok=false
    $ok
}

s3_incremental_excludes_days_older_than_last_recorded() {
    local repo
    repo="$(fresh_repo later-day)" || return 1
    commit_file "$repo" "2026-06-09T12:00:00 +0000" "old.txt" "old" "add old change" || return 1
    commit_file "$repo" "2026-06-10T12:00:00 +0000" "feature.txt" "feature" "add recorded-day change" || return 1
    write_changelog_with_newest_day "$repo" "2026-06-10"
    commit_file "$repo" "2026-06-11T12:00:00 +0000" "new.txt" "new" "add later-day change" || return 1

    local dates expected
    dates="$(documented_dates "$repo")"
    expected=$'2026-06-10\n2026-06-11'
    assert_eq "older day excluded, recorded and later days included" "$dates" "$expected"
}

s4_first_run_enumerates_full_history() {
    local repo
    repo="$(fresh_repo first-run)" || return 1
    commit_file "$repo" "2026-06-08T12:00:00 +0000" "first.txt" "first" "add first change" || return 1
    commit_file "$repo" "2026-06-10T12:00:00 +0000" "second.txt" "second" "add second change" || return 1

    local dates expected
    dates="$(documented_dates "$repo")"
    expected=$'2026-06-08\n2026-06-10'
    assert_eq "first run uses all distinct commit dates" "$dates" "$expected"
}

s5_skill_text_carries_anchored_insertion() {
    local text
    text="$(cat "$SKILL_FILE")"
    local ok=true
    # Acceptance 1: stable anchor + invariant in the output contract, with the reopened-day carve-out.
    assert_contains "insertion anchor tag" "$text" "<insertion_anchor>" || ok=false
    assert_contains "anchor invariant seam" "$text" "immediately between the end of the header block and the current first" || ok=false
    assert_contains "anchor governs new sections only" "$text" "governs **new** day sections only" || ok=false
    assert_contains "reopened-day carve-out extends in place" "$text" "extended in place per \`<last_recorded_day_reconciliation>\`" || ok=false
    # Acceptance 2: incremental single anchored prepend vs cold-build per-day insert against the same anchor.
    assert_contains "incremental prepend tag" "$text" "<incremental_prepend>" || ok=false
    assert_contains "single-block newest-first prepend" "$text" "compose all the run's new day sections into one block already ordered newest-first" || ok=false
    assert_contains "one splicing insert" "$text" "a single insert that splices that block into the seam" || ok=false
    assert_contains "cold build insert tag" "$text" "<cold_build_insert>" || ok=false
    assert_contains "cold build per-day insert same seam" "$text" "insert each completed day section into the same seam" || ok=false
    assert_contains "post-loop single splice step" "$text" "<land_new_days>" || ok=false
    # Acceptance 3: bounded read to find the seam, not a whole-file read.
    assert_contains "bounded seam read" "$text" "bounded read of only the header block plus the first existing" || ok=false
    # Acceptance 6: rescoped context safety as one canonical passage.
    assert_contains "blob released on both paths" "$text" "one day at a time on **both** paths" || ok=false
    assert_contains "section flush is the cold-build rule" "$text" "the separate cold-build rule" || ok=false
    assert_contains "incremental holds sections, no per-day flush" "$text" "no per-day section flush" || ok=false
    # Acceptance 6: prior unconditional per-day-section-flush wording superseded.
    assert_not_contains "no unconditional flush-each-day wording" "$text" "flush each completed day section to \`CHANGELOG.md\` before moving to the next" || ok=false
    # Acceptance 2: loose "insert directly after the header" phrasing gone.
    assert_not_contains "loose insert-after-header phrasing gone" "$text" "insert new day sections directly after the header" || ok=false
    # Acceptance 4: reworded prose stays self-contained — no sibling-task link leaks in.
    assert_not_contains "no sibling task incremental-day-boundaries" "$text" "incremental-day-boundaries" || ok=false
    assert_not_contains "no sibling task immutable-entries" "$text" "immutable-entries" || ok=false
    assert_not_contains "no sibling task large-output-protocol" "$text" "large-output-protocol" || ok=false
    $ok
}

s6_anchored_prepend_yields_newest_first() {
    # Acceptance 5: demonstrate that the operation <newest_first> specifies — one
    # anchored prepend of a newest-first block into the seam between the header block
    # and the first existing day heading — yields newest-first order with every
    # pre-existing day unchanged and in its original order.
    local dir="$SCRATCH/anchored-prepend"
    rm -rf "$dir"
    mkdir -p "$dir"
    local cl="$dir/CHANGELOG.md"

    # Existing changelog: header block + two settled days, newest-first.
    cat > "$cl" <<'EOF'
# CHANGELOG — Harness

Entries are grouped strictly by day, kept on their original implementation dates, and immutable once written.

## 2026-06-10 — Existing Newer Day

- **added:** Older-but-newest recorded entry.
- **Files changed:** `b.txt`

---

## 2026-06-08 — Existing Older Day

- **added:** Oldest recorded entry.
- **Files changed:** `a.txt`

---
EOF

    # Snapshot the pre-existing day sections verbatim, to prove they stay untouched.
    local existing_before
    existing_before="$(awk '/^## 2026-06-10/{f=1} f' "$cl")"

    # The run's two new days composed into ONE block, already ordered newest-first
    # (2026-06-12 above 2026-06-11), as <incremental_prepend> specifies.
    local block
    block="$(cat <<'EOF'
## 2026-06-12 — New Newest Day

- **added:** New entry for the newest day.
- **Files changed:** `d.txt`

---

## 2026-06-11 — New Middle Day

- **added:** New entry for the middle day.
- **Files changed:** `c.txt`

---
EOF
)"

    # Locate the seam (first "## " heading) and splice the block immediately above it:
    # one insert, anchored on the first existing day heading. A bounded operation — the
    # header block and everything below the seam are copied through untouched.
    local seam_line spliced
    seam_line="$(grep -n '^## ' "$cl" | head -1 | cut -d: -f1)"
    spliced="$(head -n "$((seam_line - 1))" "$cl"; printf '%s\n\n' "$block"; tail -n "+$seam_line" "$cl")"

    local ok=true
    # All four day headings are newest-first after the single prepend.
    local order
    order="$(printf '%s\n' "$spliced" | grep '^## ' | awk '{print $2}' | tr '\n' ' ' | sed 's/ $//')"
    assert_eq "four days newest-first after single prepend" "$order" "2026-06-12 2026-06-11 2026-06-10 2026-06-08" || ok=false
    # The new newest day sits at the very top of the day list, below the header block.
    local first_heading
    first_heading="$(printf '%s\n' "$spliced" | grep '^## ' | head -1)"
    assert_eq "new newest day is the first heading" "$first_heading" "## 2026-06-12 — New Newest Day" || ok=false
    # Pre-existing day sections are byte-for-byte unchanged and still in original order.
    local existing_after
    existing_after="$(printf '%s\n' "$spliced" | awk '/^## 2026-06-10/{f=1} f')"
    assert_eq "pre-existing day sections unchanged and in order" "$existing_after" "$existing_before" || ok=false
    # The header block survives intact above every day heading.
    assert_contains "header H1 retained" "$spliced" "# CHANGELOG — Harness" || ok=false
    assert_contains "header immutability line retained" "$spliced" "immutable once written" || ok=false
    $ok
}

s7_skill_text_carries_repo_agnostic_verification() {
    local text verify_block ok=true
    text="$(cat "$SKILL_FILE")"
    verify_block="$(awk '/<verify>/{f=1} f{print} /<\/verify>/{if (f) exit}' "$SKILL_FILE")"

    # Acceptance 1: a <verify> step discovering the repo's own tooling in priority order,
    # each entry run in the form its owner authored it, with a graceful stated skip.
    assert_contains "verify step tag" "$text" "<verify>" || ok=false
    assert_contains "priority 1 repo lint entry point" "$verify_block" "<repo_lint_entry_point>" || ok=false
    assert_contains "entry point runs as the repo authored it" "$verify_block" "in the form the repo authored it" || ok=false
    assert_contains "priority 2 project-configured linter" "$verify_block" "<project_configured_markdown_linter>" || ok=false
    assert_contains "self-invoked linter targets the changelog" "$verify_block" "pointed at \`CHANGELOG.md\`" || ok=false
    assert_contains "priority 3 graceful skip" "$verify_block" "<no_linter_available>" || ok=false
    assert_contains "skip states its reason" "$verify_block" "no repo lint tooling found; skipped markdown verification" || ok=false

    # Acceptance 2: <verify> sits inside <procedure> after <land_new_days>, reads the file as
    # it stands on disk there, and is the only procedure step carrying a lint directive.
    local proc_open proc_close land verify_at verify_end
    proc_open="$(grep -n '<procedure>' "$SKILL_FILE" | head -1 | cut -d: -f1)"
    proc_close="$(grep -n '</procedure>' "$SKILL_FILE" | head -1 | cut -d: -f1)"
    land="$(grep -n '<land_new_days>' "$SKILL_FILE" | head -1 | cut -d: -f1)"
    verify_at="$(grep -n '<verify>' "$SKILL_FILE" | head -1 | cut -d: -f1)"
    verify_end="$(grep -n '</verify>' "$SKILL_FILE" | head -1 | cut -d: -f1)"
    if [[ -z "$proc_open" || -z "$proc_close" || -z "$land" || -z "$verify_at" || -z "$verify_end" ]]; then
        log "    [placement: a procedure/land_new_days/verify marker is missing]"
        ok=false
    elif (( verify_at <= proc_open || verify_at <= land || verify_end >= proc_close )); then
        log "    [placement: <verify> must sit inside <procedure> after <land_new_days>]"
        log "      procedure: $proc_open-$proc_close, land_new_days: $land, verify: $verify_at-$verify_end"
        ok=false
    else
        local lint_outside
        lint_outside="$(grep -n 'lint' "$SKILL_FILE" \
            | awk -F: -v a="$verify_at" -v b="$verify_end" '$1 < a || $1 > b')"
        assert_eq "lint directives confined to <verify>" "$lint_outside" "" || ok=false
    fi
    assert_contains "verify reads the changelog as landed on disk" "$verify_block" "as it stands on disk at this point" || ok=false
    assert_contains "both run types verified" "$verify_block" "both run types inspect the file the run actually wrote" || ok=false

    # Acceptance 3: an outcome for each of the three branches, changelog delivered on all of them.
    assert_contains "outcome reporting tag" "$verify_block" "<report_outcome>" || ok=false
    assert_contains "clean branch outcome" "$verify_block" "report the changelog as verified against it" || ok=false
    assert_contains "findings branch reports and keeps the file" "$verify_block" "leave the file as written" || ok=false
    assert_contains "skip branch outcome" "$verify_block" "report the skip with its stated reason" || ok=false
    assert_contains "changelog stands on every branch" "$verify_block" "stands as delivered on all three branches" || ok=false

    # Acceptance 4: the verdict answers for CHANGELOG.md alone.
    assert_contains "changelog-scoped verdict tag" "$verify_block" "<changelog_scoped_verdict>" || ok=false
    assert_contains "foreign findings are pre-existing state" "$verify_block" "a file this run did not write is pre-existing repo state" || ok=false

    # Acceptance 5: the step reports and never rewrites; immutability clauses untouched.
    assert_contains "verify never rewrites the changelog" "$verify_block" "leaves the written \`CHANGELOG.md\` in place on every branch" || ok=false
    assert_contains "date immutability clause intact" "$text" "Keep entries on their original implementation date forever." || ok=false
    assert_contains "preserve existing clause intact" "$text" "Preserve existing day sections and entries in place." || ok=false

    # Acceptance 6: network-fetched linters and config-overriding default rulesets stay out.
    assert_contains "network install prohibited" "$verify_block" "npx --yes" || ok=false
    assert_contains "default ruleset override prohibited" "$verify_block" "default ruleset in place of the repo's own lint config" || ok=false

    # Acceptance 7: no normative clause assumes `make lint` exists.
    assert_not_contains "no unconditional make lint assumption" "$text" "make lint" || ok=false
    assert_contains "make target existence confirmed first" "$verify_block" "confirm the target exists with \`make -n <target>\`" || ok=false
    $ok
}

scenario "s1" "skill text carries incremental boundary rules" s1_skill_text_carries_boundary_rules
scenario "s2" "same-day later commit is included through durable file handoff" s2_same_day_incremental_reopens_last_day_with_file_handoff
scenario "s3" "incremental selection starts at the last recorded day" s3_incremental_excludes_days_older_than_last_recorded
scenario "s4" "first-run selection remains full-history" s4_first_run_enumerates_full_history
scenario "s5" "skill text carries the anchored newest-first insertion" s5_skill_text_carries_anchored_insertion
scenario "s6" "anchored prepend yields newest-first, pre-existing days untouched" s6_anchored_prepend_yields_newest_first
scenario "s7" "skill text verifies with the repo's own lint tooling, whatever it is" s7_skill_text_carries_repo_agnostic_verification

log ""
log "Passed: $PASS"
log "Failed: $FAIL"

if (( FAIL > 0 )); then
    log "Failed scenario ids: ${FAILED_IDS[*]}"
    exit 1
fi
