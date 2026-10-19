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

# One assignment each, identical to the strings in references/manual_fallback.md.
# A quoted assignment after =, :, or Go's := matches a value of eight or more
# characters, and that value may contain spaces. A value that starts with $
# stays a variable reference, quoted or not, and an unquoted Go expression
# after := stays out. An unquoted KEY=value opens its line, after an optional
# export or an optional YAML list dash such as a Compose environment item, so
# a keyword argument stays out of the scan, also one a formatter put on a line
# of its own. An indented assignment still matches when its value is quoted.
# An unquoted YAML key: value matches when its bare value runs to the end of
# the line or to a # comment, opens with a letter or digit, holds eight or
# more characters free of quotes, $, brackets, braces, parentheses, angle
# brackets, |, commas, and semicolons, and contains a digit or one of
# !@%^&*+=~. That keeps a type annotation such as SecretStr or Optional[str],
# a ${{ }} template, and a !vault tag out of the scan. An sk- key
# starts at a word boundary. A Unix home path starts the line or follows a
# character other than a letter, digit, ., _, @, or -, so a route, an import
# alias, or a URL segment named home or Users stays out. The credential
# pattern is a heredoc so its quote characters stay one greppable span.
read -r CREDENTIAL_PATTERN << 'END_CREDENTIAL_PATTERN'
AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|[^[:alnum:][:space:]]?[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|secret|SECRET|password|PASSWORD|passwd|PASSWD|token|TOKEN)[^[:alnum:][:space:]]?[[:space:]]*(:=|[:=])[[:space:]]*[^[:alnum:][:space:]:=$][^$[:space:]][^[:space:]]{7,}|^([[:space:]]*-[[:space:]]+"?|export[[:space:]]+)?[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|secret|SECRET|password|PASSWORD|passwd|PASSWD|token|TOKEN)=[^$"'[:space:]][^[:space:]]{7,}|(api[_-]?key|API[_-]?KEY|secret|SECRET|password|PASSWORD|passwd|PASSWD|token|TOKEN)[[:space:]]*(:=|[:=])[[:space:]]*["'][^"'$][^"']{7,}|^[[:space:]]*(-[[:space:]]+)?[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|secret|SECRET|password|PASSWORD|passwd|PASSWD|token|TOKEN)[[:space:]]*:[[:space:]]+([[:alnum:]][^][:space:]"'$(){}<>|,;#[]{6,}[0-9!@%^&*+=~][^][:space:]"'$(){}<>|,;#[]*|[[:alnum:]][^][:space:]"'$(){}<>|,;#[]*[0-9!@%^&*+=~][^][:space:]"'$(){}<>|,;#[]{6,}|[0-9][^][:space:]"'$(){}<>|,;#[]{7,})([[:space:]]+#.*)?[[:space:]]*$
END_CREDENTIAL_PATTERN
HOME_PATH_PATTERN='((^|[^A-Za-z0-9._@-])(/home/[A-Za-z0-9._-]+/?|/Users/[A-Za-z0-9._-]+/?)|C:\\\\Users\\\\[A-Za-z0-9._-]+|C:\\Users\\[A-Za-z0-9._-]+)'

# Pin the patch format of every diff the collector parses or the model reads.
# a/ and b/ keep diff.mnemonicPrefix and diff.noprefix from changing the
# headers that b_path and the size-profile path listing read. --no-color keeps
# color.diff=always from putting an escape sequence before a line's first
# character, and --no-ext-diff keeps diff.external and a driver's diff command
# from replacing the unified diff.
DIFF_FORMAT=(--src-prefix=a/ --dst-prefix=b/ --no-color --no-ext-diff)

# The scan cites each hit at its line in the file, so its main diffs skip
# textconv drivers, whose output numbers a converted text. A binary file whose
# only text view is its textconv driver gets a second pass, cited (textconv).
SCAN_DIFF_FLAGS=(--no-textconv)

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

# Emit the head-side path of each change, each ended by a NUL. The walk reads
# git's -z name-status, which prints every path verbatim, so a path that
# name_status.txt shows git-quoted, such as a non-ASCII name, still works as a
# pathspec. Renames and copies contribute the new path; every other status
# contributes its single path.
changed_head_paths() {
    local status path
    git diff --name-status -z -M --find-renames "$BASE...$HEAD_REF" 2>/dev/null |
        while IFS= read -r -d '' status; do
            IFS= read -r -d '' path || break
            case "$status" in
                R*|C*) IFS= read -r -d '' path || break ;;
            esac
            printf '%s\0' "$path"
        done
}

# When the whole-range diff fails because one blob is missing, keep every
# per-path result that succeeds and record the unread remainder so the report
# can name those paths instead of losing the readable ones too.
collect_range_diffs_per_path() {
    local path unread=0
    : > "$OUT/full_diff.txt"
    : > "$OUT/diff_stat.txt"
    : > "$OUT/removed_hunks.txt"
    : > "$OUT/unread_paths.txt"

    while IFS= read -r -d '' path; do
        [[ -z "$path" ]] && continue
        if git diff -M --find-renames "${DIFF_FORMAT[@]}" "$BASE...$HEAD_REF" -- "$path" \
                >> "$OUT/full_diff.txt" 2>/dev/null; then
            git diff --stat --no-color "$BASE...$HEAD_REF" -- "$path" \
                >> "$OUT/diff_stat.txt" 2>/dev/null || true
            git diff -M "${DIFF_FORMAT[@]}" "$BASE...$HEAD_REF" -- "$path" 2>/dev/null |
                grep -E '^(diff --git |---|\+\+\+|-)' \
                >> "$OUT/removed_hunks.txt" || true
        else
            printf '%s\n' "$path" >> "$OUT/unread_paths.txt"
            unread=1
        fi
    done < <(changed_head_paths)

    record "full_diff.txt" "the complete three-dot diff, readable paths kept when one path is unread"
    record "diff_stat.txt" "the three-dot diff stat, readable paths kept when one path is unread"
    record "removed_hunks.txt" "every removed line, for the retirement heading"
    if ((unread)); then
        record "unread_paths.txt" "changed paths whose new content git could not produce"
    else
        rm -f "$OUT/unread_paths.txt"
    fi
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

    step "three-dot name-status with rename detection"
    git diff --name-status -M --find-renames "$BASE...$HEAD_REF" 2>/dev/null |
        write_and_record name_status.txt "three-dot name-status with rename detection"

    step "commit list without merges"
    git log --no-merges --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF" 2>/dev/null |
        write_and_record commits_no_merges.txt "the branch commits with full messages, merges excluded"

    step "commit list along first parent"
    git log --first-parent --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF" 2>/dev/null |
        write_and_record commits_first_parent.txt "the branch commits along the first parent, so in-branch merges from the base stay visible"

    step "three-dot diff stat and full diff"
    if git diff -M --find-renames "${DIFF_FORMAT[@]}" "$BASE...$HEAD_REF" > "$OUT/full_diff.txt" 2>/dev/null; then
        git diff --stat --no-color "$BASE...$HEAD_REF" 2>/dev/null |
            write_and_record diff_stat.txt "the three-dot diff stat"
        record "full_diff.txt" "the complete three-dot diff"
        step "removed hunks view"
        git diff -M "${DIFF_FORMAT[@]}" "$BASE...$HEAD_REF" 2>/dev/null |
            grep -E '^(diff --git |---|\+\+\+|-)' |
            write_and_record removed_hunks.txt "every removed line, for the retirement heading"
    else
        step "per-path retry for unread paths"
        collect_range_diffs_per_path
    fi
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

# Walk one unified or combined diff.
# A --- or +++ line is a header only between a diff --git or diff --cc opener
# and that file's +++ path header, so a later content line that begins with
# those characters stays content. mode=counts prints "added removed" from the
# first character of each content line, which is what collect_size_profile
# matches to numstat, including a combined diff from the working-tree file.
# mode=added numbers a unified diff: each added line loses its leading +,
# numbering starts at the + field inside the @ runs of each @@ hunk, and an
# untracked file with no hunk header starts at 1. A blank context line, which
# diff.suppressBlankEmpty prints with no leading space, advances that number.
diff_with_header_window() {
    local mode=$1 file=$2 content=${3:-} locs=${4:-}
    awk -v mode="$mode" -v content="$content" -v locs="$locs" '
        function start_file() {
            in_header = 1
            path = ""
            lineno = 0
            past_hunk = 0
        }
        function b_path(line,   p) {
            p = line
            sub(/^\+\+\+ /, "", p)
            sub(/\t$/, "", p)
            if (substr(p, 1, 1) == "\"") sub(/^"b\//, "\"", p)
            else sub(/^b\//, "", p)
            return p
        }
        function hunk_start(line,   span, n, rest) {
            span = line
            if (match(line, /^@+ [^@]*@+/)) span = substr(line, RSTART, RLENGTH)
            rest = span
            n = 0
            while (match(rest, /\+[0-9]+/)) {
                n = substr(rest, RSTART + 1, RLENGTH - 1) + 0
                rest = substr(rest, RSTART + RLENGTH)
            }
            return n
        }
        function emit(text) {
            if (lineno + 0 == 0) lineno = 1
            if (content != "") {
                print text > content
                print path ":" lineno > locs
            }
            lineno++
        }
        function advance() {
            if (lineno + 0 == 0) lineno = 1
            lineno++
        }
        /^diff --git / { start_file(); next }
        /^diff --cc / { start_file(); next }
        in_header && /^--- / { next }
        in_header && /^\+\+\+ / {
            if (mode == "added") path = b_path($0)
            in_header = 0
            next
        }
        /^@@@/ {
            in_header = 0
            past_hunk = 1
            next
        }
        /^@@/ {
            in_header = 0
            past_hunk = 1
            if (mode == "added") lineno = hunk_start($0)
            next
        }
        past_hunk && /^$/ {
            if (mode == "added") advance()
            next
        }
        mode == "counts" {
            if ($0 ~ /^\+/) added++
            else if ($0 ~ /^-/) removed++
            next
        }
        /^\+/ { emit(substr($0, 2)); next }
        /^ / { advance(); next }
        END {
            if (mode == "counts") printf "%d %d\n", added + 0, removed + 0
        }
    ' "$file"
}

# One grep over the added-line file, joined back to path:line by line number.
scan_pattern_hits() {
    local pattern=$1 content=$2 locs=$3
    [[ -s "$content" ]] || return 0
    grep -anE "$pattern" "$content" | awk -v locs="$locs" -v content="$content" '
        BEGIN {
            n = 0
            while ((getline line < locs) > 0) loc[++n] = line
            close(locs)
            n = 0
            while ((getline line < content) > 0) body[++n] = line
            close(content)
        }
        {
            num = $0
            sub(/:.*/, "", num)
            num += 0
            if (num > 0 && loc[num] != "") printf "  %s:%s\n", loc[num], body[num]
        }
    ' || true
}

# Append each staged added line that the working-tree walk does not carry for
# the same path, located at its index line and marked (staged). A line staged
# and then removed from the working file is what the next commit records, so
# it stays in the scan although the reader cannot open it in the working tree.
append_index_only() {
    local content=$1 locs=$2 index_content=$3 index_locs=$4
    awk -v content="$content" -v locs="$locs" \
        -v icontent="$index_content" -v ilocs="$index_locs" '
        function path_of(loc,   p) {
            p = loc
            sub(/ \(textconv\)$/, "", p)
            sub(/:[0-9]+$/, "", p)
            return p
        }
        BEGIN {
            while ((getline loc < locs) > 0) {
                if ((getline text < content) <= 0) text = ""
                seen[path_of(loc) SUBSEP text] = 1
            }
            close(locs)
            close(content)
            while ((getline loc < ilocs) > 0) {
                if ((getline text < icontent) <= 0) text = ""
                if ((path_of(loc) SUBSEP text) in seen) continue
                print text >> content
                print loc " (staged)" >> locs
            }
            close(ilocs)
            close(icontent)
        }
    '
}

# Print the textconv diff of each path that the raw diff with the same
# arguments shows as binary, so a binary file whose only text view is its
# textconv driver is still scanned. numstat -z prints a binary path as - - and a
# rename as an empty path followed by the old and new names. A binary path with
# no textconv driver stays binary here and adds no line.
write_textconv_diffs() {
    local rec added removed path old
    git diff --numstat -z "${SCAN_DIFF_FLAGS[@]}" "$@" 2>/dev/null |
        while IFS= read -r -d '' rec; do
            added=${rec%%$'\t'*}
            rec=${rec#*$'\t'}
            removed=${rec%%$'\t'*}
            path=${rec#*$'\t'}
            old=""
            if [[ -z "$path" ]]; then
                IFS= read -r -d '' old || break
                IFS= read -r -d '' path || break
            fi
            [[ "$added" == "-" && "$removed" == "-" ]] || continue
            git -c core.quotepath=false diff "${DIFF_FORMAT[@]}" --textconv "$@" \
                -- ${old:+"$old"} "$path" 2>/dev/null || true
        done
}

# Walk one more diff and append its added lines, each location followed by
# the marker, so a hit says which kind of text its line number counts.
append_marked_walk() {
    local diff=$1 content=$2 locs=$3 marker=$4
    local more_content="$OUT/.scan_more_content" more_locs="$OUT/.scan_more_locs"
    : > "$more_content"
    : > "$more_locs"
    diff_with_header_window added "$diff" "$more_content" "$more_locs"
    cat "$more_content" >> "$content"
    sed "s/\$/$marker/" "$more_locs" >> "$locs"
    rm -f "$more_content" "$more_locs"
}

# Credential shapes and machine-specific absolute home paths are both cheap to
# spot in the added lines and expensive to find after a merge.
collect_secret_scan() {
    local source content locs cred_lines home_lines scan_diff="" scan_base path
    local index_diff="" index_content="$OUT/.scan_index_content" index_locs="$OUT/.scan_index_locs"
    local textconv_diff="" index_textconv_diff=""
    step "credential and home-path scan of the added lines"

    if [[ -f "$OUT/full_diff.txt" ]]; then
        # The evidence diff keeps git's quoting. The scan names each path as
        # it appears on disk, including a non-ASCII name.
        scan_diff="$OUT/.scan_diff"
        if ! git -c core.quotepath=false diff -M --find-renames "${DIFF_FORMAT[@]}" "${SCAN_DIFF_FLAGS[@]}" \
                "$BASE...$HEAD_REF" > "$scan_diff" 2>/dev/null; then
            # The whole-range diff failed, so scan the same per-path diffs the
            # evidence retry kept. A path git cannot produce adds nothing and
            # stays named in unread_paths.txt.
            : > "$scan_diff"
            while IFS= read -r -d '' path; do
                [[ -z "$path" ]] && continue
                git -c core.quotepath=false diff -M --find-renames "${DIFF_FORMAT[@]}" "${SCAN_DIFF_FLAGS[@]}" \
                    "$BASE...$HEAD_REF" -- "$path" >> "$scan_diff" 2>/dev/null || true
            done < <(changed_head_paths)
        fi
        source="$scan_diff"
        textconv_diff="$OUT/.scan_textconv_diff"
        write_textconv_diffs -M --find-renames "$BASE...$HEAD_REF" > "$textconv_diff"
    elif [[ -f "$OUT/worktree_diff.txt" ]]; then
        # Number against the working tree. The staged lane of worktree_diff.txt
        # is git diff --cached, whose line numbers are the index, so a file
        # edited again after staging would cite a line the reader does not open.
        scan_diff="$OUT/.scan_diff"
        # An unborn branch has no HEAD. Diff that tree against the empty tree
        # so staged content is still scanned at working-tree lines.
        scan_base=$(git rev-parse --verify -q HEAD || git hash-object -t tree /dev/null)
        {
            git -c core.quotepath=false diff "$scan_base" "${DIFF_FORMAT[@]}" "${SCAN_DIFF_FLAGS[@]}" 2>/dev/null || true
            write_untracked_diffs
        } > "$scan_diff"
        source="$scan_diff"
        textconv_diff="$OUT/.scan_textconv_diff"
        write_textconv_diffs "$scan_base" > "$textconv_diff"
        # The staged lane joins the scan for the lines only the index holds.
        index_diff="$OUT/.scan_index_diff"
        git -c core.quotepath=false diff --cached "${DIFF_FORMAT[@]}" "${SCAN_DIFF_FLAGS[@]}" \
            > "$index_diff" 2>/dev/null || true
        index_textconv_diff="$OUT/.scan_index_textconv_diff"
        write_textconv_diffs --cached > "$index_textconv_diff"
    else
        source=""
    fi

    content="$OUT/.scan_content"
    locs="$OUT/.scan_locs"
    : > "$content"
    : > "$locs"
    if [[ -n "$source" ]]; then
        diff_with_header_window added "$source" "$content" "$locs"
    fi
    if [[ -n "$textconv_diff" ]]; then
        append_marked_walk "$textconv_diff" "$content" "$locs" " (textconv)"
    fi
    if [[ -n "$index_diff" ]]; then
        : > "$index_content"
        : > "$index_locs"
        diff_with_header_window added "$index_diff" "$index_content" "$index_locs"
        append_marked_walk "$index_textconv_diff" "$index_content" "$index_locs" " (textconv)"
        append_index_only "$content" "$locs" "$index_content" "$index_locs"
    fi
    cred_lines=$(scan_pattern_hits "$CREDENTIAL_PATTERN" "$content" "$locs")
    home_lines=$(scan_pattern_hits "$HOME_PATH_PATTERN" "$content" "$locs")
    rm -f "$content" "$locs" "$scan_diff" "$index_diff" "$index_content" "$index_locs" \
        "$textconv_diff" "$index_textconv_diff"

    {
        printf 'credential_pattern_hits:\n'
        if [[ -n "$cred_lines" ]]; then
            printf '%s\n' "$cred_lines"
        else
            printf '  none\n'
        fi
        printf 'hardcoded_home_path_hits:\n'
        if [[ -n "$home_lines" ]]; then
            printf '%s\n' "$home_lines"
        else
            printf '  none\n'
        fi
    } | write_and_record secret_scan.txt "credential patterns and hardcoded home paths among the added lines"
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

# Print the path of each generated section and each binary section in a diff
# whose openers all use the diff --git form. Each path comes from its section's
# opener, which every section has, and every opener sets the current path, so
# a Binary files line names the section it belongs to whatever form it takes:
# modified, added or deleted against /dev/null, or the bare form a conflicted
# binary gets. The path takes the form git diff --name-only prints. A renamed
# section names its new path on its rename to line, which git writes in that
# form, so each section prints its path once at its end, after any rename to
# line has set it. Every other section keeps the opener's first path. A quoted
# name keeps git's quotes and its escapes up to the closing quote. An unquoted
# name loses its a/ prefix and ends where the second path's b/ starts: at the
# midpoint when both sides name one path, so a name holding spaces or " b/"
# stays whole, and otherwise at the first " b/" or ' "b/'. The generated match
# reads the whole opener line, as the generated_files count does.
# GENERATED_PATTERN reaches awk through the environment, where awk applies no
# escape processing to it.
binary_and_generated_paths() {
    GENERATED_PATTERN="$GENERATED_PATTERN" LC_ALL=C awk '
        function first_path(line,   rest, n, half) {
            rest = line
            sub(/^diff --git /, "", rest)
            if (match(rest, /^"a\/([^"\\]|\\.)*"/)) {
                return "\"" substr(rest, 4, RLENGTH - 3)
            }
            sub(/^a\//, "", rest)
            n = length(rest)
            half = (n - 3) / 2
            if (half > 0 && half == int(half) && substr(rest, half + 1, 3) == " b/" &&
                substr(rest, 1, half) == substr(rest, half + 4)) {
                return substr(rest, 1, half)
            }
            sub(/ "?b\/.*$/, "", rest)
            return rest
        }
        function flush() {
            if (path != "" && (generated || binary)) print path
        }
        /^diff --git / {
            flush()
            path = first_path($0)
            generated = ($0 ~ ENVIRON["GENERATED_PATTERN"])
            binary = 0
            next
        }
        /^rename to / {
            path = substr($0, 11)
            next
        }
        /^Binary files |^GIT binary patch/ {
            binary = 1
        }
        END { flush() }
    ' "$1"
}

# Binary and generated files inflate a diff without carrying reviewable intent,
# so the report states their share whether or not they hold findings.
collect_size_profile() {
    local source="$OUT/full_diff.txt"
    [[ -f "$source" ]] || source="$OUT/worktree_diff.txt"
    step "diff size and the binary and generated share"

    # git diff opens the combined diff of a path both sides of an unresolved
    # merge changed with diff --cc and the bare path. Every field below reads
    # one copy of the diff with each such opener rewritten into the diff --git
    # form, quotes kept, and every other line unchanged. A conflicted file then
    # counts as a section, matches GENERATED_PATTERN through its a/ prefix, and
    # names its path as an ordinary file does. The collector runs git diff
    # without -c, so no diff --combined opener appears. LC_ALL=C lets sed pass
    # a content line that is not valid text in the current locale.
    local diff="$OUT/.size_profile_diff"
    if ! LC_ALL=C sed -E -e 's#^diff --cc "(.*)"$#diff --git "a/\1" "b/\1"#' -e 't' \
            -e 's#^diff --cc (.*)$#diff --git a/\1 b/\1#' "$source" > "$diff" 2>/dev/null; then
        : > "$diff"
    fi

    {
        local total binary generated
        total=$(count_matches '^diff --git ' "$diff")
        binary=$(count_matches '^Binary files |^GIT binary patch' "$diff")
        generated=$(grep -E '^diff --git ' "$diff" 2>/dev/null |
            count_matches_piped "$GENERATED_PATTERN")

        # Count content lines only. The shared header window skips each file's
        # --- / +++ pair, a conflicted file's included, and leaves content that
        # begins with those characters once the header is past. Matches git
        # diff --numstat on the same changes.
        local added_lines removed_lines counts
        counts=$(diff_with_header_window counts "$diff")
        added_lines=${counts%% *}
        removed_lines=${counts##* }

        printf 'changed_files: %s\n' "$total"
        printf 'added_lines: %s\n' "$added_lines"
        printf 'removed_lines: %s\n' "$removed_lines"
        printf 'binary_files: %s\n' "$binary"
        printf 'generated_files: %s\n' "$generated"
        if ((total > 0)); then
            printf 'binary_or_generated_share: %s%%\n' "$(( (binary + generated) * 100 / total ))"
        else
            printf 'binary_or_generated_share: 0%%\n'
        fi
        printf 'binary_or_generated_paths:\n'
        binary_and_generated_paths "$diff" | sort -u | sed 's/^/  /'
    } | write_and_record size_profile.txt "the diff size and the share of binary and generated files"
    rm -f "$diff"
}

# Untracked names come back unquoted, so a name git would quote still names
# the file on disk. Each file is a new-file diff whose first line is line 1.
# sed keeps a missing final newline missing, so that file ends the way git ends
# it, and the next file's header starts a line of its own. A symlink is the
# path it points to, which is what git records, so the file at the other end
# is never read into the evidence.
write_untracked_diffs() {
    local f
    while IFS= read -r -d '' f; do
        [[ -z "$f" ]] && continue
        printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n' "$f" "$f" "$f"
        if [[ -L "$f" ]]; then
            printf '+%s\n\\ No newline at end of file\n' "$(readlink "$f")"
        elif [[ -f "$f" ]]; then
            if sed 's/^/+/' "$f" 2>/dev/null; then
                if [[ -s "$f" && $(tail -c 1 "$f" | wc -l) -eq 0 ]]; then
                    printf '\n\\ No newline at end of file\n'
                fi
            else
                printf '+<unreadable>\n'
            fi
        fi
    done < <(git -c core.quotepath=false ls-files -z --others --exclude-standard)
    return 0
}

collect_uncommitted() {
    step "working-tree lane: status, diff, and untracked content"
    git status --porcelain --untracked-files=all |
        write_and_record worktree_status.txt "the staged, unstaged, and untracked paths"

    {
        printf '### staged\n'
        git diff --cached "${DIFF_FORMAT[@]}" 2>/dev/null
        printf '\n### unstaged\n'
        git diff "${DIFF_FORMAT[@]}" 2>/dev/null
        printf '\n### untracked\n'
        write_untracked_diffs
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
    page_thread_comments "$OUT/forge/review_threads.json"
    record "forge/review_threads.json" "the inline review threads across every page, each thread's comments across every page, resolved and outdated ones kept"
}

# The thread id and comment endCursor of every thread whose comments run past
# the page the thread connection returned, one tab-separated pair per line.
threads_with_more_comments() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    threads = json.load(open(sys.argv[1])).get("threads", [])
except Exception:
    sys.exit(0)
for t in threads:
    info = (t.get("comments") or {}).get("pageInfo") or {}
    if t.get("id") and info.get("hasNextPage") and info.get("endCursor"):
        print(f"{t['id']}\t{info['endCursor']}")
PY
}

# The endCursor of a thread-comments page that has a next one, and the empty
# string otherwise.
comment_page_cursor() {
    python3 - "$1" <<'PY' 2>/dev/null
import json, sys
try:
    info = json.load(open(sys.argv[1]))["data"]["node"]["comments"]["pageInfo"]
    print(info["endCursor"] if info.get("hasNextPage") else "")
except Exception:
    print("")
PY
}

# Fold every fetched comment page into its thread, in fetch order, and carry
# the last page's pageInfo so the merged thread shows where its comments end.
fold_comment_pages() {
    python3 - "$1" "$2" <<'PY' 2>/dev/null
import json, pathlib, sys
merged = pathlib.Path(sys.argv[1])
index = pathlib.Path(sys.argv[2]) / "index.tsv"
if not index.exists():
    sys.exit(0)
data = json.loads(merged.read_text())
threads = {t.get("id"): t for t in data.get("threads", [])}
followed = 0
for line in index.read_text().splitlines():
    thread_id, page_file = line.split("\t", 1)
    try:
        conn = json.loads(pathlib.Path(page_file).read_text())["data"]["node"]["comments"]
    except Exception:
        continue
    thread = threads.get(thread_id)
    if thread is None:
        continue
    comments = thread.setdefault("comments", {})
    comments.setdefault("nodes", []).extend(conn.get("nodes") or [])
    comments["pageInfo"] = conn.get("pageInfo") or {}
    followed += 1
data["comment_pages"] = followed
merged.write_text(json.dumps(data, indent=2))
PY
}

# A thread's comments page on their own connection, so a long thread read from
# its first page alone drops the later replies that settle or reopen it. Follow
# each thread's comment cursor through the thread's node id and fold the later
# pages into that thread.
page_thread_comments() {
    local merged="$1" dir="$OUT/forge/.comment_pages" thread cursor n=0 pages
    rm -rf "$dir"
    mkdir -p "$dir"
    : > "$dir/index.tsv"

    # The dollar signs below are GraphQL variables and stay literal.
    # shellcheck disable=SC2016
    local query='query($id:ID!,$cursor:String){
  node(id:$id){
    ... on PullRequestReviewThread{
      comments(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ author{ login } body createdAt }
      }
    }
  }
}'

    while IFS=$'\t' read -r thread cursor; do
        [[ -n "$thread" && -n "$cursor" ]] || continue
        pages=0
        while [[ -n "$cursor" ]] && ((pages < 20)); do
            pages=$((pages + 1))
            n=$((n + 1))
            if ! gh api graphql -f "id=$thread" -f "cursor=$cursor" -f "query=$query" \
                    > "$dir/page_$n.json" 2>/dev/null; then
                rm -f "$dir/page_$n.json"
                break
            fi
            printf '%s\t%s\n' "$thread" "$dir/page_$n.json" >> "$dir/index.tsv"
            cursor="$(comment_page_cursor "$dir/page_$n.json")"
        done
    done < <(threads_with_more_comments "$merged")

    fold_comment_pages "$merged" "$dir"
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
    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die_env "not inside a git repository"

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

    cd "$repo_root" || die_env "not inside a git repository"

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
