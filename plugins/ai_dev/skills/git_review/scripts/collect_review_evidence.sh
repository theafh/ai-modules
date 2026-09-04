#!/usr/bin/env bash
# collect_review_evidence.sh - gather the git layer, and the forge layer when it
# is reachable, into one scratch directory of plain files for /git_review.
#
# The model reads the written files instead of issuing dozens of commands, so
# the evidence set is fixed and the same for every run. Bash is required for
# arrays and [[ ]]. `set -e` stays off on purpose: a missing optional surface
# (no `gh`, no upstream, no CI workflow) is a recorded absence rather than a
# failed run, so each command's status is inspected where it is run.

set -uo pipefail

EXIT_USAGE=1
EXIT_ENV=2

MODE=branch
BASE=""
HEAD_REF=""
OUT=""
PR_NUMBER=""
DO_FETCH=yes

# One definition of what counts as a generated or vendored path, used by both
# the count and the path listing so the two never disagree.
GENERATED_PATTERN='(_generated\.|\.generated\.|_pb2\.py|\.pb\.go|/vendor/|/node_modules/|/dist/|\.min\.(js|css)|\.lock|\.snap)'

usage() {
    cat <<'USAGE'
collect_review_evidence.sh - collect review evidence into a scratch directory.

Usage:
  collect_review_evidence.sh --base <ref> --head <ref> [--out <dir>] [--pr <number>] [--no-fetch]
  collect_review_evidence.sh --uncommitted [--base <ref>] [--out <dir>] [--no-fetch]
  collect_review_evidence.sh --help

Modes:
  branch (default)  Compare <head> against <base> across the merge base, which
                    is the shape a branch review and a pull request review share.
  --uncommitted     Review the working tree (staged, unstaged, and untracked)
                    plus the local commits ahead of the upstream, reported as
                    two separate lanes.

Behavior:
  - Fetches the base and head refs before any diff, so a stale local base does
    not inflate the diff and a stale local head does not review the wrong code.
    --no-fetch skips that step for an offline or already-fetched run.
  - Writes every artifact into the output directory and lists them all in
    manifest.txt, with the ordered step log in steps.log.
  - Reads the forge layer through `gh` when it is installed, authenticated, and
    the remote is a GitHub repository, and records the absence otherwise.
  - Reads the repository only. It creates no commit, moves no ref, and changes
    no file in the working tree.

Exit codes:
  0  the evidence directory is complete; its path is the last stdout line
  1  usage error
  2  environment error (git missing, or not inside a git repository)
USAGE
}

die() {
    printf 'git_review: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

die_env() {
    printf 'git_review: %s\n' "$*" >&2
    exit "$EXIT_ENV"
}

step() {
    printf '%s\n' "$1" >> "$OUT/steps.log"
}

# Record every artifact as it is written, so the manifest names the evidence set
# rather than a directory listing taken at the end.
record() {
    printf '%-34s %s\n' "$1" "$2" >> "$OUT/manifest.txt"
}

write_and_record() {
    local name="$1" desc="$2"
    cat > "$OUT/$name"
    record "$name" "$desc"
}

ref_exists() {
    git rev-parse --verify --quiet "$1^{commit}" >/dev/null 2>&1
}

# Resolve a ref the caller named to something this clone can diff: the ref
# itself when it exists locally, otherwise the remote-tracking form.
resolve_ref() {
    local ref="$1" remote
    if ref_exists "$ref"; then
        printf '%s' "$ref"
        return 0
    fi
    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue
        if ref_exists "$remote/$ref"; then
            printf '%s' "$remote/$ref"
            return 0
        fi
    done < <(git remote)
    return 1
}

fetch_refs() {
    if [[ "$DO_FETCH" != yes ]]; then
        step "fetch skipped (--no-fetch)"
        write_and_record fetch.log "the fetch step, skipped by --no-fetch" <<< "fetch skipped by --no-fetch"
        return 0
    fi

    step "fetch base and head refs"
    {
        printf 'git fetch --all --no-prune\n'
        git fetch --all --no-prune 2>&1 || printf 'fetch exited non-zero; continuing from the refs already present\n'
    } | write_and_record fetch.log "the fetch that precedes every diff"
}

collect_target() {
    local reviewed
    reviewed="$(git rev-parse "$HEAD_REF" 2>/dev/null)"
    {
        printf 'mode: %s\n' "$MODE"
        printf 'base: %s\n' "$BASE"
        printf 'head: %s\n' "$HEAD_REF"
        printf 'reviewed_commit: %s\n' "${reviewed:-unresolved}"
        printf 'pull_request: %s\n' "${PR_NUMBER:-none}"
        printf 'head_branch: %s\n' "$(git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'DETACHED')"
        printf 'worktree_state: %s\n' \
            "$([[ -n "$(git status --porcelain --untracked-files=all)" ]] && printf 'dirty' || printf 'clean')"
    } | write_and_record target.txt "the resolved target and the reviewed commit"
}

# A local branch that is behind its upstream reviews the wrong code, and nothing
# else in the evidence set says so: counts.txt measures head against the base,
# not against the head's own remote. Without this file the fast-forward decision
# has no input, so a stale local head is reviewed silently.
collect_head_sync() {
    local branch upstream local_sha remote_sha counts behind ahead state
    step "head against its own upstream"

    branch="$HEAD_REF"
    # Strip a remote prefix so `origin/topic` and `topic` both name the branch
    # whose upstream is being read.
    while IFS= read -r remote; do
        [[ -n "$remote" && "$branch" == "$remote/"* ]] && branch="${branch#"$remote"/}"
    done < <(git remote)

    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name "$branch@{upstream}" 2>/dev/null)"
    local_sha="$(git rev-parse --verify --quiet "refs/heads/$branch^{commit}" 2>/dev/null)"
    [[ -n "$upstream" ]] && remote_sha="$(git rev-parse --verify --quiet "$upstream^{commit}" 2>/dev/null)"

    if [[ -z "$local_sha" ]]; then
        state="no local branch; the remote ref is the only head"
    elif [[ -z "$upstream" ]]; then
        state="no upstream configured"
    elif [[ "$local_sha" == "${remote_sha:-}" ]]; then
        state="in sync"
    else
        counts="$(git rev-list --left-right --count "$upstream...refs/heads/$branch" 2>/dev/null)"
        behind="$(printf '%s' "${counts:-0	0}" | cut -f1)"
        ahead="$(printf '%s' "${counts:-0	0}" | cut -f2)"
        if ((behind > 0 && ahead > 0)); then
            state="diverged: behind $behind, ahead $ahead"
        elif ((behind > 0)); then
            state="behind $behind"
        else
            state="ahead $ahead"
        fi
    fi

    {
        printf 'branch: %s\n' "$branch"
        printf 'upstream: %s\n' "${upstream:-none}"
        printf 'local_head: %s\n' "${local_sha:-none}"
        printf 'remote_head: %s\n' "${remote_sha:-none}"
        printf 'head_vs_upstream: %s\n' "$state"
        printf 'reviewed_ref: %s\n' "$HEAD_REF"
        printf 'reviewed_commit: %s\n' "$(git rev-parse "$HEAD_REF" 2>/dev/null || printf 'unresolved')"
    } | write_and_record head_sync.txt "the head against its own upstream, which decides the fast-forward"
}

collect_range() {
    local mb
    step "merge base and ahead/behind counts"
    mb="$(git merge-base "$BASE" "$HEAD_REF" 2>/dev/null)"
    printf '%s\n' "${mb:-unresolved}" | write_and_record merge_base.txt "the merge base of base and head"

    {
        local counts
        counts="$(git rev-list --left-right --count "$BASE...$HEAD_REF" 2>/dev/null)"
        printf 'base_ahead_of_head\thead_ahead_of_base\n'
        printf '%s\n' "${counts:-0	0}"
        printf 'behind: %s\n' "$(printf '%s' "${counts:-0	0}" | cut -f1)"
        printf 'ahead: %s\n' "$(printf '%s' "${counts:-0	0}" | cut -f2)"
    } | write_and_record counts.txt "how far head is ahead of and behind base"

    step "three-dot diff stat"
    git diff --stat "$BASE...$HEAD_REF" 2>/dev/null |
        write_and_record diff_stat.txt "the three-dot diff stat"

    step "three-dot name-status with rename detection"
    git diff --name-status -M --find-renames "$BASE...$HEAD_REF" 2>/dev/null |
        write_and_record name_status.txt "three-dot name-status with rename detection"

    step "commit list without merges"
    git log --no-merges --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF" 2>/dev/null |
        write_and_record commits_no_merges.txt "the branch commits with full messages, merges excluded"

    step "commit list along first parent"
    git log --first-parent --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF" 2>/dev/null |
        write_and_record commits_first_parent.txt "the branch commits along the first parent, so in-branch merges from the base stay visible"

    step "full three-dot diff"
    git diff -M --find-renames "$BASE...$HEAD_REF" 2>/dev/null |
        write_and_record full_diff.txt "the complete three-dot diff"

    step "removed hunks view"
    git diff -M "$BASE...$HEAD_REF" 2>/dev/null |
        grep -E '^(diff --git |---|\+\+\+|-)' |
        write_and_record removed_hunks.txt "every removed line, for the retirement heading"
}

# The base side of a deleted or renamed path is gone from the head tree, so read
# it from the base commit rather than from the worktree.
collect_base_side() {
    local status path old renamed_to
    step "base-side git show of deleted files and prior versions"
    mkdir -p "$OUT/base_side"

    : > "$OUT/base_side/index.txt"
    while IFS=$'\t' read -r status path renamed_to; do
        [[ -z "$status" ]] && continue
        case "$status" in
            D*|R*|M*) old="$path" ;;
            *) continue ;;
        esac
        local flat="${old//\//__}"
        if git show "$BASE:$old" > "$OUT/base_side/$flat" 2>/dev/null; then
            printf '%s\t%s\t%s\tbase_side/%s\n' \
                "$status" "$old" "${renamed_to:-$old}" "$flat" >> "$OUT/base_side/index.txt"
        fi
    done < "$OUT/name_status.txt"

    record "base_side/" "the base-side content of every deleted, renamed, and modified path"
    record "base_side/index.txt" "status, path, and stored file for each base-side version"
}

collect_test_merge() {
    step "test merge with git merge-tree"
    local out rc
    out="$(git merge-tree --write-tree --name-only "$BASE" "$HEAD_REF" 2>&1)"
    rc=$?
    printf '%s\n' "$out" | write_and_record merge_tree.txt "the git merge-tree test merge against the base"

    {
        if ((rc == 0)); then
            printf 'conflicts: none\n'
            printf 'structurally_mergeable: yes\n'
        else
            printf 'conflicts: yes\n'
            printf 'structurally_mergeable: no\n'
            printf 'conflicting_files:\n'
            printf '%s\n' "$out" | tail -n +2 | while IFS= read -r line; do
                [[ -n "$line" ]] && printf '  %s\n' "$line"
            done
        fi
    } | write_and_record conflicts.txt "whether the test merge conflicts, and which files do"
}

# Credential shapes and machine-specific absolute home paths are both cheap to
# spot in the added lines and expensive to find after a merge.
collect_secret_scan() {
    local added="$OUT/.added_lines"
    step "credential and home-path scan of the added lines"

    if [[ -f "$OUT/full_diff.txt" ]]; then
        grep -E '^\+' "$OUT/full_diff.txt" | grep -v '^+++' > "$added" 2>/dev/null
    elif [[ -f "$OUT/worktree_diff.txt" ]]; then
        grep -E '^\+' "$OUT/worktree_diff.txt" | grep -v '^+++' > "$added" 2>/dev/null
    else
        : > "$added"
    fi

    {
        printf 'credential_pattern_hits:\n'
        grep -nE 'AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{16,}|sk-[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(api[_-]?key|secret|password|passwd|token)[[:space:]]*[:=][[:space:]]*["'"'"'][^"'"'"']{8,}' \
            "$added" 2>/dev/null | sed 's/^/  /' || printf '  none\n'
        printf 'hardcoded_home_path_hits:\n'
        grep -nE '(/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/|C:\\\\Users\\\\[A-Za-z0-9._-]+)' \
            "$added" 2>/dev/null | sed 's/^/  /' || printf '  none\n'
    } | write_and_record secret_scan.txt "credential patterns and hardcoded home paths among the added lines"

    rm -f "$added"
}

# grep -c prints 0 and exits 1 when nothing matches, so a `|| printf 0` fallback
# would emit the count twice. This helper always prints exactly one integer.
count_matches() {
    local pattern="$1" file="$2" n
    n="$(grep -cE "$pattern" "$file" 2>/dev/null)" || n=0
    printf '%s' "${n:-0}"
}

count_matches_piped() {
    local n
    n="$(grep -cE "$1" 2>/dev/null)" || n=0
    printf '%s' "${n:-0}"
}

# Binary and generated files inflate a diff without carrying reviewable intent,
# so the report states their share whether or not they hold findings.
collect_size_profile() {
    local source="$OUT/full_diff.txt"
    [[ -f "$source" ]] || source="$OUT/worktree_diff.txt"
    step "diff size and the binary and generated share"

    {
        local total binary generated
        total=$(count_matches '^diff --git ' "$source")
        binary=$(count_matches '^Binary files |^GIT binary patch' "$source")
        generated=$(grep -E '^diff --git ' "$source" 2>/dev/null |
            count_matches_piped "$GENERATED_PATTERN")

        printf 'changed_files: %s\n' "$total"
        printf 'added_lines: %s\n' "$(count_matches '^\+' "$source")"
        printf 'removed_lines: %s\n' "$(count_matches '^-' "$source")"
        printf 'binary_files: %s\n' "$binary"
        printf 'generated_files: %s\n' "$generated"
        if ((total > 0)); then
            printf 'binary_or_generated_share: %s%%\n' "$(( (binary + generated) * 100 / total ))"
        else
            printf 'binary_or_generated_share: 0%%\n'
        fi
        printf 'binary_or_generated_paths:\n'
        {
            grep -E '^diff --git ' "$source" 2>/dev/null |
                grep -E "$GENERATED_PATTERN" |
                sed 's/^diff --git a\///; s/ b\/.*$//'
            grep -E '^Binary files ' "$source" 2>/dev/null |
                sed 's/^Binary files a\///; s/ and b\/.*$//'
        } | sort -u | sed 's/^/  /'
    } | write_and_record size_profile.txt "the diff size and the share of binary and generated files"
}

collect_uncommitted() {
    step "working-tree lane: status, diff, and untracked content"
    git status --porcelain --untracked-files=all |
        write_and_record worktree_status.txt "the staged, unstaged, and untracked paths"

    {
        printf '### staged\n'
        git diff --cached 2>/dev/null
        printf '\n### unstaged\n'
        git diff 2>/dev/null
        printf '\n### untracked\n'
        git ls-files --others --exclude-standard 2>/dev/null | while IFS= read -r f; do
            [[ -z "$f" ]] && continue
            printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n' "$f" "$f" "$f"
            if [[ -f "$f" ]]; then
                sed 's/^/+/' "$f" 2>/dev/null || printf '+<unreadable>\n'
            fi
        done
    } | write_and_record worktree_diff.txt "the working-tree lane as one diff, untracked content included"

    step "local-commits lane: commits ahead of the upstream"
    local upstream
    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)"
    {
        if [[ -n "$upstream" ]]; then
            printf 'upstream: %s\n' "$upstream"
            printf 'ahead: %s\n' "$(git rev-list --count "$upstream..HEAD" 2>/dev/null || printf 0)"
            printf '\n'
            git log --format='%H%n%an%n%ad%n%B%n---' "$upstream..HEAD" 2>/dev/null
        else
            printf 'upstream: none configured\n'
            printf 'ahead: unknown\n'
        fi
    } | write_and_record local_commits.txt "the local commits ahead of the upstream"
}

# Every other history walk here is scoped to the branch, so a finding that rests
# on a guardrail document has nowhere to find the precedent it must cite beside
# it. This searches the history the branch grew out of, keyed on the changed
# paths and on the guardrail names, and stays cheap by capping what it reads.
collect_precedent() {
    local f path
    step "precedent search over prior history"
    mkdir -p "$OUT/precedent"

    # Per changed path: the commits that touched it before this branch.
    : > "$OUT/precedent/by_path.txt"
    while IFS=$'\t' read -r _status path _rest; do
        [[ -z "$path" ]] && continue
        {
            printf '### %s\n' "$path"
            git log --no-merges --max-count=5 --format='%h %ad %s' --date=short \
                "$BASE" -- "$path" 2>/dev/null
            printf '\n'
        } >> "$OUT/precedent/by_path.txt"
    done < <(head -n 40 "$OUT/name_status.txt" 2>/dev/null)
    record "precedent/by_path.txt" "the commits that touched each changed path before this branch"

    # Per guardrail document present: the commits whose message cites it, which
    # is where a prior change that met or crossed the same constraint shows up.
    : > "$OUT/precedent/by_guardrail.txt"
    for f in CHARTER.md ARCHITECTURE.md TESTING.md SECURITY.md; do
        [[ -f "$f" ]] || continue
        {
            printf '### %s\n' "$f"
            git log --no-merges --max-count=10 --format='%h %ad %s' --date=short \
                --grep="${f%.md}" --regexp-ignore-case "$BASE" 2>/dev/null
            printf '\n'
        } >> "$OUT/precedent/by_guardrail.txt"
    done
    [[ -s "$OUT/precedent/by_guardrail.txt" ]] ||
        printf 'no guardrail documents present\n' > "$OUT/precedent/by_guardrail.txt"
    record "precedent/by_guardrail.txt" "the prior commits whose messages cite each guardrail document"
}

collect_gates() {
    step "gate list from the workflow definition and the documented entry points"
    {
        printf 'ci_workflow_files:\n'
        local found=no f
        for f in .github/workflows/*.yml .github/workflows/*.yaml \
                 .gitlab-ci.yml .circleci/config.yml; do
            if [[ -f "$f" ]]; then
                printf '  %s\n' "$f"
                found=yes
            fi
        done
        [[ "$found" == no ]] && printf '  none found\n'

        printf 'documented_entry_points:\n'
        for f in Makefile Justfile justfile Taskfile.yml package.json noxfile.py tox.ini; do
            [[ -f "$f" ]] && printf '  %s\n' "$f"
        done

        printf 'standing_instruction_files:\n'
        for f in CLAUDE.md AGENTS.md GEMINI.md CONTRIBUTING.md; do
            [[ -f "$f" ]] && printf '  %s\n' "$f"
        done

        printf 'guardrail_documents:\n'
        for f in CHARTER.md ARCHITECTURE.md TESTING.md SECURITY.md; do
            [[ -f "$f" ]] && printf '  %s\n' "$f"
        done
    } | write_and_record gates.txt "the CI workflow definitions, documented entry points, standing instructions, and guardrail documents present"
}

collect_forge() {
    step "forge layer"
    mkdir -p "$OUT/forge"

    if ! command -v gh >/dev/null 2>&1; then
        printf 'forge layer unavailable: gh is not on PATH\n' |
            write_and_record forge/status.txt "why the forge layer is unavailable, or that it is available"
        return 0
    fi
    if ! gh auth status >/dev/null 2>&1; then
        printf 'forge layer unavailable: gh is installed but not authenticated\n' |
            write_and_record forge/status.txt "why the forge layer is unavailable, or that it is available"
        return 0
    fi
    # Read the configured URLs rather than `git remote -v`, whose output an
    # insteadOf rewrite replaces with the rewritten target.
    if ! git config --get-regexp '^remote\..*\.url$' 2>/dev/null | grep -qi 'github\.com'; then
        printf 'forge layer unavailable: no remote points at github.com; the git-only path applies\n' |
            write_and_record forge/status.txt "why the forge layer is unavailable, or that it is available"
        return 0
    fi

    printf 'forge layer available via gh\n' |
        write_and_record forge/status.txt "why the forge layer is unavailable, or that it is available"

    local pr_selector=()
    [[ -n "$PR_NUMBER" ]] && pr_selector=("$PR_NUMBER")

    gh pr view "${pr_selector[@]}" --json \
        number,title,body,headRefName,baseRefName,headRefOid,state,isDraft,mergeable,mergeStateStatus,reviewDecision,additions,deletions,changedFiles \
        > "$OUT/forge/pr.json" 2>"$OUT/forge/pr.err"
    record "forge/pr.json" "the pull request body, head SHA, mergeable state, and review decision"

    gh pr view "${pr_selector[@]}" --json comments > "$OUT/forge/comments.json" 2>/dev/null
    record "forge/comments.json" "the issue comments on the pull request"

    gh pr view "${pr_selector[@]}" --json reviews > "$OUT/forge/reviews.json" 2>/dev/null
    record "forge/reviews.json" "the review bodies and their states"

    gh pr view "${pr_selector[@]}" --json statusCheckRollup > "$OUT/forge/checks.json" 2>/dev/null
    record "forge/checks.json" "the continuous-integration check results for the head commit"

    # The review-thread connection is the one surface carrying each thread's
    # resolved and outdated state, and it pages on both levels.
    collect_review_threads

    gh api "repos/{owner}/{repo}/rulesets" > "$OUT/forge/rulesets.json" 2>/dev/null ||
        printf '[]\n' > "$OUT/forge/rulesets.json"
    record "forge/rulesets.json" "the branch rulesets, when they are readable"

    {
        printf 'issue_comments: %s\n' "$(count_json_array "$OUT/forge/comments.json" comments)"
        printf 'reviews: %s\n' "$(count_json_array "$OUT/forge/reviews.json" reviews)"
        printf 'review_threads: %s\n' "$(count_review_threads)"
    } | write_and_record forge/counts.txt "the count of issue comments, review bodies, and inline review threads, so an empty discussion is proven"
}

count_json_array() {
    local file="$1" key="$2"
    python3 - "$file" "$key" <<'PY' 2>/dev/null || printf 'unknown'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unknown")
    sys.exit(0)
v = d.get(sys.argv[2], d) if isinstance(d, dict) else d
print(len(v) if isinstance(v, list) else "unknown")
PY
}

count_review_threads() {
    python3 - "$OUT/forge/review_threads.json" <<'PY' 2>/dev/null || printf 'unknown'
import json, sys
try:
    d = json.load(open(sys.argv[1]))
except Exception:
    print("unknown")
    sys.exit(0)
threads = d if isinstance(d, list) else d.get("threads", [])
resolved = sum(1 for t in threads if t.get("isResolved"))
outdated = sum(1 for t in threads if t.get("isOutdated"))
print(f"{len(threads)} (resolved: {resolved}, outdated: {outdated})")
PY
}

# The endCursor of a page that has a next one, and the empty string otherwise.
page_cursor() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    d = json.load(open(sys.argv[1]))
    info = d["data"]["repository"]["pullRequest"]["reviewThreads"]["pageInfo"]
    print(info["endCursor"] if info.get("hasNextPage") else "")
except Exception:
    print("")
PY
}

# Fold every collected page into one thread list, keeping the resolved and the
# outdated threads rather than filtering them away.
merge_thread_pages() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null || printf '{"threads": [], "pages": 0}\n' > "$2"
import json, pathlib, sys
pages = sorted(pathlib.Path(sys.argv[1]).glob("page_*.json"),
               key=lambda p: int(p.stem.split("_")[1]))
threads = []
for page in pages:
    try:
        d = json.loads(page.read_text())
    except Exception:
        continue
    conn = (d.get("data", {}).get("repository", {})
             .get("pullRequest", {}).get("reviewThreads", {}))
    threads.extend(conn.get("nodes", []) or [])
json.dump({"threads": threads, "pages": len(pages)}, open(sys.argv[2], "w"), indent=2)
PY
}

# Page the thread connection and the comment connection inside each thread, and
# keep the resolved and outdated threads rather than filtering them away.
collect_review_threads() {
    local number
    number="$PR_NUMBER"
    if [[ -z "$number" ]]; then
        number="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("number",""))' \
            "$OUT/forge/pr.json" 2>/dev/null)"
    fi

    if [[ -z "$number" ]]; then
        printf '{"threads": [], "note": "no pull request number resolved"}\n' > "$OUT/forge/review_threads.json"
        record "forge/review_threads.json" "the inline review threads with their resolved and outdated state"
        return 0
    fi

    # The dollar signs below are GraphQL variables and stay literal.
    # shellcheck disable=SC2016
    local query='query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
  repository(owner:$owner,name:$repo){
    pullRequest(number:$number){
      reviewThreads(first:50, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{
          id isResolved isOutdated path line
          comments(first:100){
            pageInfo{ hasNextPage endCursor }
            nodes{ author{ login } body createdAt }
          }
        }
      }
    }
  }
}'

    # One file per page rather than one accumulating stream: a page's JSON may
    # arrive pretty-printed, so each page is parsed as a whole document.
    local cursor="" page=0 pages_dir="$OUT/forge/.thread_pages"
    rm -rf "$pages_dir"
    mkdir -p "$pages_dir"
    while :; do
        page=$((page + 1))
        local args=(api graphql -F "owner={owner}" -F "repo={repo}" -F "number=$number" -f "query=$query")
        [[ -n "$cursor" ]] && args+=(-F "cursor=$cursor")
        if ! gh "${args[@]}" > "$pages_dir/page_$page.json" 2>/dev/null; then
            rm -f "$pages_dir/page_$page.json"
            break
        fi
        cursor="$(page_cursor "$pages_dir/page_$page.json")"
        [[ -z "$cursor" ]] && break
        ((page >= 20)) && break
    done

    merge_thread_pages "$pages_dir" "$OUT/forge/review_threads.json"
    record "forge/review_threads.json" "the inline review threads across every page, resolved and outdated ones kept"
}

main() {
    while (($# > 0)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --base) BASE="${2:?--base needs a ref}"; shift 2 ;;
            --head) HEAD_REF="${2:?--head needs a ref}"; shift 2 ;;
            --out) OUT="${2:?--out needs a directory}"; shift 2 ;;
            --pr) PR_NUMBER="${2:?--pr needs a number}"; shift 2 ;;
            --uncommitted) MODE=uncommitted; shift ;;
            --no-fetch) DO_FETCH=no; shift ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    command -v git >/dev/null 2>&1 || die_env "git was not found on PATH"
    git rev-parse --show-toplevel >/dev/null 2>&1 || die_env "not inside a git repository"

    if [[ "$MODE" == branch ]]; then
        [[ -n "$BASE" ]] || die "--base is required in branch mode"
        [[ -n "$HEAD_REF" ]] || die "--head is required in branch mode"
    else
        HEAD_REF="${HEAD_REF:-HEAD}"
    fi

    if [[ -z "$OUT" ]]; then
        OUT="$(mktemp -d "${TMPDIR:-/tmp}/git_review.XXXXXX")"
    else
        mkdir -p "$OUT"
        OUT="$(cd "$OUT" && pwd)"
    fi
    : > "$OUT/manifest.txt"
    : > "$OUT/steps.log"
    record "manifest.txt" "this list of collected evidence files"
    record "steps.log" "the ordered log of collection steps"

    fetch_refs

    if [[ "$MODE" == branch ]]; then
        local resolved_base resolved_head
        resolved_base="$(resolve_ref "$BASE")" || die "base ref resolves nowhere: $BASE"
        resolved_head="$(resolve_ref "$HEAD_REF")" || die "head ref resolves nowhere: $HEAD_REF"
        BASE="$resolved_base"
        HEAD_REF="$resolved_head"
        collect_target
        collect_head_sync
        collect_range
        collect_base_side
        collect_test_merge
        collect_precedent
    else
        BASE="${BASE:-HEAD}"
        collect_target
        collect_uncommitted
    fi

    collect_secret_scan
    collect_size_profile
    collect_gates
    collect_forge

    step "done"
    printf 'Evidence collected. Read manifest.txt first, then each named file.\n'
    printf '%s\n' "$OUT"
}

main "$@"
