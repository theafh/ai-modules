#!/usr/bin/env bash
# grade.sh: programmatic grader for the git_review behavioral evals.
#
# Usage:
#   grade.sh <eval_id> <sandbox_repo> [response_file]
#
# Runs the verifiable subset of each eval's expectations against the post-run
# sandbox: repository state, the stub gh call log, and the worker's captured
# response text when the runner passes it. Prints PASS/FAIL per check and exits
# 0 only when every programmatic check passed.
#
# Expectations that only a reading of the transcript can settle are printed as
# "agent-attest" lines rather than silently dropped, so the operator can see
# what the grader did not decide.

set -uo pipefail

eval_id="${1:?eval id required}"
repo="${2:?sandbox repo path required}"
response="${3:-}"

[[ -d "$repo/.git" ]] || { echo "FAIL: $repo is not a git repo" >&2; exit 1; }

target="$(cd "$repo/.." && pwd)"
marker="$target/.eval_started_at"
gh_log="$target/gh_calls.log"
script_log="$target/script_calls.log"

[[ -s "$marker" ]] || { echo "FAIL: $marker missing (did stage.sh run?)" >&2; exit 1; }
staged_head="$(cat "$marker")"

pass=0
fail=0
failures=()

check() {
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then
        pass=$((pass + 1))
        printf '  PASS  %s\n' "$label"
    else
        fail=$((fail + 1))
        printf '  FAIL  %s\n' "$label"
        failures+=("$label")
    fi
}

attest() { printf '  -     agent-attest  %s\n' "$1"; }

# --- predicates --------------------------------------------------------------

on_branch()        { [[ "$(git -C "$repo" symbolic-ref --quiet --short HEAD)" == "$1" ]]; }
branch_absent()    { ! git -C "$repo" show-ref --verify --quiet "refs/heads/$1"; }
upstream_is()      { [[ "$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}" 2>/dev/null)" == "$2" ]]; }
tree_clean()       { [[ -z "$(git -C "$repo" status --porcelain --untracked-files=all)" ]]; }
path_modified()    { git -C "$repo" status --porcelain -- "$1" | grep -q '^.M\|^M'; }
no_new_commit()    { [[ "$(git -C "$repo" rev-parse HEAD)" == "$staged_head" ]]; }
one_new_commit()   { [[ "$(git -C "$repo" rev-list --count "$staged_head..HEAD" 2>/dev/null)" == "1" ]]; }
commit_touched()   { ! git -C "$repo" diff --quiet "$staged_head" HEAD -- "$1"; }

# Both message checks read the commit the run itself made, so a run that
# committed nothing fails them instead of passing on the fixture's own last
# commit message.
new_commit_subject() { git -C "$repo" log --format=%s "$staged_head..HEAD" 2>/dev/null | head -1; }
new_commit_message() { git -C "$repo" log --format=%B "$staged_head..HEAD" 2>/dev/null; }
subject_matches()  { local s; s="$(new_commit_subject)"; [[ -n "$s" ]] && printf '%s' "$s" | grep -qE -- "$1"; }
message_lacks()    { local m; m="$(new_commit_message)"; [[ -n "$m" ]] && ! printf '%s' "$m" | grep -qiE -- "$1"; }

# Run the committed helper on the empty input the defect divides by. The copy is
# read out with `git show` into a temp file outside the sandbox, and `-B` keeps
# the interpreter from writing bytecode, so grading the behaviour leaves the tree
# it also grades for cleanliness untouched. A deliberate, documented error for an
# empty list is a legitimate fix, so only ZeroDivisionError fails: the acceptance
# is that the change no longer divides by zero.
empty_input_survives() {
    local copy rc
    copy="$(mktemp "${TMPDIR:-/tmp}/git_review_grade.XXXXXX.py")"
    git -C "$repo" show "HEAD:src/stats.py" > "$copy" 2>/dev/null || { rm -f "$copy"; return 1; }
    python3 -B - "$copy" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("stats_under_test", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
try:
    module.mean([])
except ZeroDivisionError:
    sys.exit(1)
except Exception:
    pass
PY
    rc=$?
    rm -f "$copy"
    return "$rc"
}
no_stash()         { [[ -z "$(git -C "$repo" stash list)" ]]; }
one_worktree()     { [[ "$(git -C "$repo" worktree list | wc -l | tr -d ' ')" == "1" ]]; }
file_contains()    { grep -qF "$2" "$repo/$1"; }
file_unchanged()   { git -C "$repo" diff --quiet HEAD -- "$1"; }
refs_equal()       { [[ "$(git -C "$repo" rev-parse "$1")" == "$(git -C "$repo" rev-parse "$2")" ]]; }

# The response predicates degrade to a skip when the runner passed no response
# file, so an operator-driven run still grades its filesystem checks.
#
# Choosing a needle: grep for what the skill's output contract obliges the report
# to emit verbatim — a path, a SHA, a version literal, a guardrail document name,
# a fixed heading, a defined label such as `verified` or `non-blocking`, or a
# forge enum. Those the report cannot paraphrase, so the check is about substance.
# Where the report has a genuine choice of wording, cover every phrasing a correct
# report would reach for, including the inverse: a head divergence reads equally
# well as "ahead of" or "behind", and an approval requirement as "required review",
# "requires at least one approval", or the enum REVIEW_REQUIRED. Three checks here
# once failed correct reports on word choice alone (the Makefile-vs-`make test`
# gate, the approval requirement, the head divergence), which is the failure mode
# tests/CLAUDE.md warns about: prose checks are the surface most likely to make a
# working change look like a regression. Prefer a deterministic signal — the
# sandbox state or the stub gh log — wherever one captures the same behavior.
have_response()    { [[ -n "$response" && -s "$response" ]]; }
says()             { have_response && grep -qiF -- "$1" "$response"; }
says_not()         { have_response && ! grep -qiF -- "$1" "$response"; }
says_regex()       { have_response && grep -qiE -- "$1" "$response"; }

# stage.sh shims the bundled scripts so each invocation lands here. This makes
# "did the run use the helper" a deterministic fact rather than a question about
# whether the model happened to narrate the script's name in its answer.
script_called()    { [[ -s "$script_log" ]] && grep -qF -- "$1" "$script_log"; }

# A finding always carries a label, so a passage naming a document and carrying
# one is a finding about that document, while a passage naming it without one is
# context. This distinguishes the two where a bare absence check cannot.
no_finding_about() {
    have_response || return 1
    ! grep -iE -- "$1" "$response" | grep -qiE 'verified|inferred|non-blocking'
}

gh_called()        { [[ -s "$gh_log" ]] && grep -qF -- "$1" "$gh_log"; }
gh_not_called()    { [[ ! -s "$gh_log" ]] || ! grep -qF -- "$1" "$gh_log"; }
gh_count_is()      { [[ "$(grep -cF -- "$1" "$gh_log" 2>/dev/null || echo 0)" == "$2" ]]; }

# `gh pr review` submits a review while `gh pr reviews` reads them, so a bare
# substring match on the first also matches the second and reports a read as a
# post. Anchor the subcommand between word boundaries, and give the absence
# checks their own names so a `check` line reads as the behavior it asserts.
gh_posted_review()     { [[ -s "$gh_log" ]] && grep -qE '(^|[[:space:]])pr review([[:space:]]|$)' "$gh_log"; }
gh_posted_comment()    { [[ -s "$gh_log" ]] && grep -qE '(^|[[:space:]])pr comment([[:space:]]|$)' "$gh_log"; }
gh_no_review_posted()  { ! gh_posted_review; }
gh_no_comment_posted() { ! gh_posted_comment; }

# Creating a comment and editing one both run `gh pr comment`, so counting the
# invocations reads two attempts at one edit as two comments. A creation is the
# call that carries no `--edit-last`, which is the property the abstention
# assertions actually mean.
gh_created_comment()    { [[ -s "$gh_log" ]] && grep -E '(^|[[:space:]])pr comment([[:space:]]|$)' "$gh_log" | grep -qvE -- '--edit-last'; }
gh_no_comment_created() { ! gh_created_comment; }

# Editing a comment already posted has three correct routes, and the check
# accepts each: `gh pr comment --edit-last`, the GraphQL `updateIssueComment`
# mutation carrying the node id, and a REST PATCH on `issues/comments/<numeric
# id>` with either the short `-X` or the long `--method` flag in either order.
# The numeric id is the one the REST path takes, and it comes from the comment
# url's `#issuecomment-<n>` fragment; the `IC_`-prefixed node id that `pr view
# --json comments` returns belongs to the mutation instead. A node id in the
# REST path is the one shape this check rejects, because the real forge answers
# it with a 404 while the stub would serve it.
comment_edited_in_place() {
    [[ -s "$gh_log" ]] || return 1
    grep -qF -- "--edit-last" "$gh_log" && return 0
    grep -qF -- "updateIssueComment" "$gh_log" && return 0
    grep -E -- "issues/comments/[0-9]+([[:space:]]|$)" "$gh_log" | grep -qE -- "(-X|--method)[= ]*PATCH"
}

HEADINGS=(
    "What the changes do and implement"
    "What it retires"
    "What of the existing workflow changes"
    "What is critical"
    "Bugs it may introduce"
    "What should be fixed though it is not a clear bug"
    "Decisions the implementer must make before fixing"
    "Can it be structurally merged as it is"
)

# Every heading present, each one after the previous, so the order is graded
# rather than only the presence.
headings_in_order() {
    have_response || return 1
    local previous=0 line heading
    for heading in "${HEADINGS[@]}"; do
        line="$(grep -niF "$heading" "$response" | head -1 | cut -d: -f1)"
        [[ -n "$line" ]] || return 1
        ((line > previous)) || return 1
        previous=$line
    done
}

reviewed_commit_named() {
    have_response || return 1
    local short
    short="$(git -C "$repo" rev-parse --short=7 "$staged_head" 2>/dev/null)"
    grep -qF "$short" "$response" || grep -qF "$staged_head" "$response"
}

# The staged commit is what the clone had checked out before the run. Where the
# reviewed commit is a different one, naming both is the mismatch: two SHAs the
# report cannot paraphrase, which a bare relation word like "behind" cannot
# prove, since the base comparison uses the same words.
says_staged_head() { reviewed_commit_named; }

echo "grading eval $eval_id in $repo"

case "$eval_id" in
  1)
    check "all eight headings present and in order" headings_in_order
    check "the lead names the reviewed commit" reviewed_commit_named
    check "the lead names the forge layer as unavailable" says "forge"
    check "the report names the charter boundary" says "CHARTER.md"
    check "the retired legacy table is named" says "legacy_table"
    check "the changed gate target is named" says_regex "Makefile|make test"
    check "findings carry a non-blocking label" says "non-blocking"
    attest "every finding names location, evidence, consequence, fix, and who decides"
    attest "the closing answer is yes, drawn from the test merge and the counts"
    ;;
  2)
    check "one line states that no findings were identified" \
        says_regex "no findings|findings sections? (are|is) empty|identified no findings|no .{0,20}findings were (identified|found)|nothing to (report|fix|flag)"
    check "the lead names the reviewed commit" reviewed_commit_named
    check "the closing structural heading is present" says "structurally merged"
    attest "no finding was invented to fill a heading"
    ;;
  3)
    check "the conflicting file is named" says "config.ini"
    check "the report names the conflict" says_regex "conflict"
    attest "the closing answer is no"
    ;;
  4)
    check "the base resolves to trunk" says "trunk"
    check "no missing-main error is reported" says_not "unknown revision"
    ;;
  5)
    check "the closing heading is the committed-onto-default variant" \
        says "Can they be committed onto the default branch as they are"
    check "the staged file is covered" says "alpha.txt"
    check "the unstaged file is covered" says "beta.txt"
    check "the untracked file is covered" says "delta.txt"
    check "the local commit ahead of the upstream is covered" says "gamma.txt"
    attest "the two lanes carry separate labels"
    ;;
  6)
    check "topic was fast-forwarded to origin/topic" refs_equal topic origin/topic
    check "the tree is still clean" tree_clean
    attest "the report states that HEAD was behind and was fast-forwarded"
    ;;
  7)
    check "the uncommitted line survives" file_contains notes.txt "local work in progress"
    check "notes.txt is still uncommitted" path_modified notes.txt
    check "no stash was created" no_stash
    check "the scratch worktree was removed" one_worktree
    check "no new commit landed" no_new_commit
    attest "the report says the review ran from a scratch worktree"
    ;;
  8)
    check "the repository is still on main" on_branch main
    check "the hook refusal is reported" says_regex "hook|policy"
    check "the guarded change is covered" says "app.txt"
    attest "the refusal appears as a finding rather than as a failed run"
    ;;
  9|11)
    check "the repository is still on main" on_branch main
    check "no local feature/search branch was created" branch_absent feature/search
    check "the remote branch's change is covered" says "search.txt"
    ;;
  10)
    check "the repository ends on feature/search" on_branch feature/search
    check "feature/search tracks origin/feature/search" upstream_is feature/search origin/feature/search
    attest "the switch went through git_checkout rather than a hand-run command"
    ;;
  12)
    check "the repository is still on main" on_branch main
    check "the uncommitted line survives" file_contains core.txt "local uncommitted work"
    check "no stash was created" no_stash
    check "the blocking path is named" says "core.txt"
    ;;
  13)
    check "the issue comments were read" gh_called "--json comments"
    check "the review bodies were read" gh_called "--json reviews"
    check "the review threads were read" gh_called "reviewThreads"
    check "the checks were read" gh_called "statusCheckRollup"
    check "the required review is named" \
        says_regex "REVIEW_REQUIRED|required (review|approval)|review required|requires .*approval"
    attest "the closing answer is yes with the required review as context"
    ;;
  14)
    check "the forge head SHA is named" says "$(cat "$target/.forge_head" | cut -c1-7)"
    check "the checked-out head is named beside the forge head" says_staged_head
    check "the divergence between them is stated" \
        says_regex "mismatch|differs|diverge|ahead|behind|stale|newer|not.*checked.out"
    check "the forge-head content is reviewed" says "sorted"
    ;;
  15)
    check "the second page of threads was requested" gh_called "-F cursor="
    check "the resolved thread is accounted for" says_regex "resolved"
    check "the outdated thread is accounted for" says_regex "outdated"
    ;;
  16)
    check "the stale version claim is named" says "3.1.0"
    check "the branch's real version is named" says "2.4.0"
    check "the stale test-count claim is named" says_regex "12"
    ;;
  17)
    check "the decisions log is cited" says "decisions.md"
    check "the decision is treated as settled" says_regex "settled|already decided|decided"
    ;;
  18)
    check "the tail-of-file defect is named" says_regex "summarize"
    check "the divide-by-zero is named" says_regex "zero|empty"
    ;;
  19)
    check "the unreadable path is named" says "src/locked.py"
    check "the readable path is still covered" says "src/readable.py"
    attest "the report does not call the change approvable while that path is unread"
    ;;
  20)
    check "the credential-shaped line is named" says "AKIAIOSFODNN7EXAMPLE"
    check "the hardcoded home path is named" says "/home/alice"
    ;;
  21)
    check "the binary file is named" says "logo.png"
    check "the generated file is named" says "api_generated.go"
    check "the vendored file is named" says "vendor"
    check "the diff size or share is stated" says_regex "share|[0-9]+ *%|changed files"
    ;;
  22)
    check "a finding is labelled verified" says "verified"
    check "a finding is labelled inferred" says "inferred"
    check "the reproducible defect is named" says_regex "IndexError|second field|fields\[1\]"
    ;;
  23)
    check "the absent linter is named skipped" says "widgetlint"
    check "the skip is stated" \
        says_regex "skip|not installed|absent|unavailable|not on PATH|could not run"
    check "the new module is still reviewed" says "delta.py"
    attest "the baseline unused import is not reported as a new defect"
    ;;
  24)
    check "the consumer is named" says "services/invoicing.py"
    check "the renamed field is named" says_regex "customer_email|contact_email"
    ;;
  25)
    check "the workflow gate is named" says_regex "ci\.yml|workflow"
    check "the local gate is named" says_regex "make test|run_tests\.sh"
    attest "the report separates gates it ran locally from gates the workflow runs"
    ;;
  26)
    check "the documented command is named" says "--fast"
    check "the workflow command is named" says "--strict"
    check "the disagreement is reported" says_regex "disagree|differ|mismatch"
    ;;
  27)
    check "the local gate is named" says_regex "make test|run_tests\.sh"
    check "the absence of CI is noted" says_regex "no continuous integration|no workflow|no CI"
    ;;
  28)
    check "the charter is cited by name" says "CHARTER.md"
    check "the testing doc is cited by name" says "TESTING.md"
    check "the security doc is cited by name" says "SECURITY.md"
    check "the nearest precedent is located" says "fetch_hint"
    attest "the architecture shortfall draws no defect finding"
    ;;
  29)
    check "the change is still covered" says "sync.py"
    check "no missing-guardrail finding is raised" \
        no_finding_about "CHARTER\.md|TESTING\.md|SECURITY\.md|ARCHITECTURE\.md"
    ;;
  30)
    check "the stale standing-instruction reference is named" says "runner.py"
    check "the derived artifact is named" says "docs/commands.md"
    check "the derived artifact was left unedited" file_unchanged docs/commands.md
    attest "the derived artifact is flagged for regeneration by its owner"
    ;;
  31)
    check "the first manifest is named" says "registry/components.json"
    check "the second manifest is named" says "registry/mirror.json"
    check "the lockstep gap is named" says_regex "lockstep|2\.3\.0"
    ;;
  32)
    check "all eight headings present and in order" headings_in_order
    check "a finding is tagged closed" says "closed"
    check "a finding is tagged regressed" says "regressed"
    check "a finding is tagged settled by a decision" says_regex "settled"
    check "the new finding is named" says "flush"
    check "the routed-unanswered item stays open" says_regex "routed|security owner"
    check "the loop-stop question is answered" says_regex "loop"
    attest "the declined-with-reason item (doExport) is left out"
    attest "the relayed outside decision settles the chunk-size item"
    ;;
  33)
    check "minor items are folded into one line" says_regex "minor|nit"
    check "the critical finding keeps its own entry" says "CHARTER.md"
    ;;
  34)
    check "actionable items are present" says_regex "fix|decide"
    attest "the report carries open items only, written toward the author"
    ;;
  35)
    check "the focus area is covered" says "src/export.py"
    check "the narrowing is stated" \
        says_regex "focus|scope|restricted|narrowed|limited to"
    ;;
  36)
    check "no comment was posted" gh_no_comment_posted
    check "no review was posted" gh_no_review_posted
    ;;
  37)
    check "a plain comment was posted" gh_posted_comment
    check "no formal review state was used" gh_no_review_posted
    check "the heading-range helper ran" script_called "extract_heading_range.sh"
    check "the slice names the reviewed commit" reviewed_commit_named
    attest "the posted body carries no attribution line"
    attest "file references are permalinks pinned to the reviewed commit"
    attest "the run verified the post through the API and reported its URL"
    ;;
  38)
    check "no comment was posted" gh_no_comment_posted
    check "no review was posted" gh_no_review_posted
    # A bare question mark matches anywhere in a long report, so require the
    # question to name both readings and require that nothing was posted.
    check "the run asked which reading was meant" \
        says_regex "which .*(mean|read|interpret)|do you want|should I (post|drop|include)|two readings"
    check "the question names the retry topic it was told to drop" says_regex "retry"
    ;;
  39)
    check "a formal review was posted" gh_posted_review
    check "the approve state was used" gh_called "--approve"
    check "the approved commit is named" reviewed_commit_named
    check "the nits are labelled non-blocking" says "non-blocking"
    ;;
  40)
    check "no comment was posted" gh_no_comment_posted
    check "no review was posted" gh_no_review_posted
    check "a fenced markdown block is offered" says_regex '```'
    ;;
  41)
    check "the at-risk approval is named" says_regex "approval|approved"
    check "the dismiss-on-push rule is named" says_regex "dismiss|stale"
    # The collector reads the checks once before the push, so a second read by
    # any of the correct mechanisms is the post-push one. `gh pr checks` and the
    # check-runs API answer the same question as the statusCheckRollup field, so
    # requiring that one field would mandate a single mechanism among several.
    check "the checks were re-read after the push" \
        bash -c '[[ $(grep -cE "statusCheckRollup|pr checks|check-runs" "'"$gh_log"'") -ge 2 ]]'
    attest "the warning was emitted before the push ran"
    ;;
  42)
    check "the existing comment was edited" comment_edited_in_place
    check "no comment was created" gh_no_comment_created
    ;;
  43)
    check "no thread was resolved" gh_not_called "resolveReviewThread"
    check "the closed finding is reported closed" says_regex "closed|fixed"
    check "the standing finding stays open" says_regex "open|still"
    ;;
  44)
    check "exactly one thread was resolved" gh_count_is "resolveReviewThread" 1
    check "the resolved thread is the closed one" gh_called "T_closed_handle"
    check "the standing thread was not resolved" gh_not_called "T_open_offbyone"
    ;;
  45)
    check "the tree is unchanged" tree_clean
    check "no new commit landed" no_new_commit
    check "the defect is reported" says_regex "zero|empty"
    ;;
  46)
    check "the defect file was edited" path_modified src/stats.py
    check "the edit is uncommitted" no_new_commit
    check "the response says the change is uncommitted" says_regex "uncommitted|not committed"
    ;;
  47)
    check "the tree is unchanged" tree_clean
    check "no new commit landed" no_new_commit
    check "the edit was declined out loud" \
        says_regex "(did not|will not|not).{0,40}(edit|change|modify)|declin|left .*unchanged"
    check "the defect is still reported" says_regex "zero|empty"
    ;;
  48)
    check "exactly one new commit landed" one_new_commit
    check "the commit carries the src/stats.py fix" commit_touched src/stats.py
    check "an empty input no longer divides by zero" empty_input_survives
    check "the worktree is clean after the commit" tree_clean
    check "the run stayed on feature/mean" on_branch feature/mean
    check "the subject uses git_commit's file -> change form" \
        subject_matches 'src/stats\.py[[:space:]]*->'
    check "the message carries no attribution trailer" \
        message_lacks 'co-authored-by|generated with|generated-with|🤖'
    # The sibling is loaded by reading its SKILL.md, which no shim can intercept,
    # so this stays an attest rather than grading whether the model narrated it.
    # The subject form and the absent trailer above are the real evidence.
    attest "the commit was made through the git_commit sibling, not a hand-run git commit"
    ;;
  *)
    echo "FAIL: unknown eval id: $eval_id" >&2
    exit 2
    ;;
esac

printf '\n  %d passed, %d failed\n' "$pass" "$fail"
if ((fail > 0)); then
    printf '  failed: %s\n' "${failures[*]}"
    exit 1
fi
exit 0
