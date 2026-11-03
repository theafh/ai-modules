#!/usr/bin/env bash
# run_round_diff.sh - write one git_auto_review round's fixer-write diff.
#
# Rebuilds the round's pre-fix state from the three artefacts
# run_snapshot.sh wrote - `pre-fix.patch`, `pre-fix.untracked.tar`, and
# `pre-fix.ignored.manifest` - and compares it with the working tree over the
# tracked, untracked, and ignored file set the snapshot, the
# concurrent-modification guard, and Restore read. The comparison leaves out
# the run's own `.git_auto_review/` folder and the harness run-output trees
# this repository regenerates.
#
# The diff is `diff -U0`: a file the fixer added is one whole-file addition, a
# file it deleted is one whole-file removal, and a tracked file it modified is
# its own hunk. An ignored path appears only when it is present now and absent
# from the manifest, because a pre-existing ignored file's content is not
# captured and stays as the fixer left it. A path whose content is binary - a
# NUL byte or bytes that are not valid UTF-8 - carries a path-only hunk in
# place of file content, so the diff stays valid UTF-8 and the verifier maps
# the hunk by path.
#
# Usage:
#   run_round_diff.sh --round <n> [--stem <name>] [--root <dir>]
#
# Exit codes:
#   0  the round diff is written; its path is the last stdout line
#   1  usage error
#   2  environment error (git missing, not in a repository, a missing
#      artefact, or a write failed)

set -uo pipefail

EXIT_USAGE=1
EXIT_ENV=2

STEM=""
ROUND=""
ROOT=""

usage() {
    cat <<'USAGE'
run_round_diff.sh - write one git_auto_review round's fixer-write diff.

Usage:
  run_round_diff.sh --round <n> [--stem <name>] [--root <dir>]
  run_round_diff.sh --help

Behavior:
  - Resolves the repository root with `git rev-parse --show-toplevel`, or uses
    --root when it is given.
  - Uses the run stem from --stem, or `default` when it is absent, and reads
    `.git_auto_review/<stem>/pre-fix.patch`,
    `.git_auto_review/<stem>/pre-fix.untracked.tar`, and
    `.git_auto_review/<stem>/pre-fix.ignored.manifest`.
  - Rebuilds the pre-fix state, compares it with the working tree over the
    tracked, untracked, and ignored file set, and writes
    `.git_auto_review/<stem>/round-r<round>.diff.txt` as a `diff -U0`.
  - Leaves out the run's own `.git_auto_review/` folder and the harness
    run-output trees under `tests/`.
  - Writes a binary path as a path-only hunk with no file content.

Exit codes:
  0  diff written; its path is the last stdout line
  1  usage error
  2  environment error
USAGE
}

die() {
    printf 'git_auto_review: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

die_env() {
    printf 'git_auto_review: %s\n' "$*" >&2
    exit "$EXIT_ENV"
}

# Report success when the repository-root-relative path lies under the run's
# own `.git_auto_review/` folder or under a harness run-output tree this
# repository regenerates. The ignored manifest, the round diff, and Restore
# all read this one exclusion.
is_run_owned_path() {
    local path=$1 rest
    case "$path" in
        .git_auto_review/*) return 0 ;;
        tests/*) ;;
        *) return 1 ;;
    esac
    rest="/${path#tests/}/"
    case "$rest" in
        */workspace/*|*/scratch/*|*/.eval_cache/*|*/results/*|*/.vendor_probe/*)
            return 0 ;;
    esac
    case "$path" in
        tests/wiki/layer2/AS-*|tests/wiki/layer2/L2-*|tests/wiki/layer2/WI-*|tests/wiki/layer2/WU-*|tests/wiki/layer2/MP-*)
            return 0 ;;
    esac
    return 1
}

# Print one NUL-delimited flag record per NUL-delimited candidate path in the
# first list file: `yes` or `no` for membership in each later list file, in
# argument order. Each list becomes a Python set once, so a candidate costs one
# set lookup instead of a rescan of the whole list.
classify_membership() {
    python3 - "$@" <<'PY'
import sys

with open(sys.argv[1], "rb") as handle:
    candidates = handle.read().split(b"\0")
sets = []
for path in sys.argv[2:]:
    with open(path, "rb") as handle:
        sets.append(set(handle.read().split(b"\0")) - {b""})
out = sys.stdout.buffer
for candidate in candidates:
    if not candidate:
        continue
    flags = b" ".join(
        b"yes" if candidate in members else b"no" for members in sets
    )
    out.write(flags + b"\0")
PY
}

# Report success when the file holds a NUL byte or bytes that are not valid
# UTF-8. A missing file is not binary.
content_is_binary() {
    local file=$1
    [[ -e "$file" || -L "$file" ]] || return 1
    python3 - "$file" <<'PY'
import sys

try:
    data = open(sys.argv[1], "rb").read()
except OSError:
    sys.exit(1)
if b"\0" in data:
    sys.exit(0)
try:
    data.decode("utf-8")
except UnicodeDecodeError:
    sys.exit(0)
sys.exit(1)
PY
}

# Collect the tracked, untracked, and ignored paths now, plus the pre-fix
# untracked members, into the union list. The ignored-now and untracked-pre
# lists classify a path whose name the ignored enumeration returns.
collect_paths() {
    local repo_root=$1 union=$2 ignored_now=$3 untracked_tar=$4
    local untracked_pre=$5
    local record status path member probe members

    # A rename or copy record carries its original path as the next record, so
    # the loop consumes that record when the status marks a rename or copy.
    local expect_original=0
    while IFS= read -r -d '' record; do
        if ((expect_original)); then
            printf '%s\0' "$record" >> "$union"
            expect_original=0
            continue
        fi
        status="${record:0:2}"
        path="${record:3}"
        printf '%s\0' "$path" >> "$union"
        case "$status" in
            *R*|*C*) expect_original=1 ;;
        esac
    done < <(cd "$repo_root" && git status --porcelain -z --untracked-files=all)

    while IFS= read -r -d '' path; do
        is_run_owned_path "$path" && continue
        printf '%s\0' "$path" >> "$union"
        printf '%s\0' "$path" >> "$ignored_now"
    done < <(cd "$repo_root" && git ls-files --others --ignored --exclude-standard -z)

    members="$(mktemp "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")" || return 1
    probe="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")" || {
        rm -f "$members"
        return 1
    }
    if ! (cd "$probe" && tar -xf "$untracked_tar" 2>/dev/null); then
        rm -f "$members"
        rm -rf "$probe"
        return 1
    fi
    (cd "$probe" && find . \( -type f -o -type l \) -print0) \
        | while IFS= read -r -d '' member; do
            printf '%s\0' "${member#./}"
        done > "$members"
    rm -rf "$probe"
    while IFS= read -r -d '' member; do
        is_run_owned_path "$member" && continue
        printf '%s\0' "$member" >> "$union"
        printf '%s\0' "$member" >> "$untracked_pre"
    done < "$members"
    rm -f "$members"

    # Dedupe each collected list once, after collection, so a path both git
    # status and an enumeration report stays one record.
    sort -z -u "$union" -o "$union" || return 1
    sort -z -u "$ignored_now" -o "$ignored_now" || return 1
    sort -z -u "$untracked_pre" -o "$untracked_pre" || return 1
}

# Write the ignored manifest's path records to the NUL-delimited list. The
# manifest is already a NUL-delimited list of paths.
collect_manifest_paths() {
    local manifest=$1 dest=$2
    cp "$manifest" "$dest" || return 1
    return 0
}

# Build the pre-fix tree: HEAD, then the captured patch, then the captured
# untracked files.
build_pre_fix() {
    local repo_root=$1 pre=$2 patch=$3 untracked_tar=$4
    (cd "$repo_root" && git archive HEAD) | tar -x -C "$pre" || return 1
    if [[ -s "$patch" ]]; then
        (cd "$pre" && git apply -- "$patch") || return 1
    fi
    (cd "$pre" && tar -xf "$untracked_tar") || return 1
    return 0
}

emit_added() {
    local path=$1 file=$2 n
    n="$(awk 'END { print NR }' "$file")"
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    printf 'new file mode 100644\n'
    printf -- '--- /dev/null\n'
    printf '+++ b/%s\n' "$path"
    if [[ "$n" -eq 0 ]]; then
        printf '@@ -0,0 +0,0 @@\n'
        return 0
    fi
    printf '@@ -0,0 +1,%s @@\n' "$n"
    sed 's/^/+/' "$file"
    if [[ -n "$(tail -c 1 "$file")" ]]; then
        printf '\n\\ No newline at end of file\n'
    fi
}

emit_removed() {
    local path=$1 file=$2 n
    n="$(awk 'END { print NR }' "$file")"
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    printf 'deleted file mode 100644\n'
    printf -- '--- a/%s\n' "$path"
    printf -- '+++ /dev/null\n'
    if [[ "$n" -eq 0 ]]; then
        printf '@@ -0,0 +0,0 @@\n'
        return 0
    fi
    printf '@@ -1,%s +0,0 @@\n' "$n"
    sed 's/^/-/' "$file"
    if [[ -n "$(tail -c 1 "$file")" ]]; then
        printf '\n\\ No newline at end of file\n'
    fi
}

emit_modified() {
    local path=$1 pre_file=$2 work_file=$3
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    { diff -U0 "$pre_file" "$work_file" || true; } \
        | awk -v p="$path" '
            NR == 1 { print "--- a/" p; next }
            NR == 2 { print "+++ b/" p; next }
            { print }
        '
}

emit_binary_added() {
    local path=$1
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    printf 'new file mode 100644\n'
    printf 'Binary files /dev/null and b/%s differ\n' "$path"
}

emit_binary_modified() {
    local path=$1
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    printf 'Binary files a/%s and b/%s differ\n' "$path" "$path"
}

emit_binary_removed() {
    local path=$1
    printf 'diff --git a/%s b/%s\n' "$path" "$path"
    printf 'deleted file mode 100644\n'
    printf 'Binary files a/%s and /dev/null differ\n' "$path"
}

main() {
    while (($# > 0)); do
        case "$1" in
            -h|--help) usage; exit 0 ;;
            --stem) STEM="${2:?--stem needs a name}"; shift 2 ;;
            --round) ROUND="${2:?--round needs a number}"; shift 2 ;;
            --root) ROOT="${2:?--root needs a directory}"; shift 2 ;;
            *) die "unknown argument: $1" ;;
        esac
    done

    [[ "$ROUND" =~ ^[0-9]+$ ]] && [[ "$ROUND" -ge 1 ]] \
        || die "--round needs a positive integer"
    command -v python3 >/dev/null 2>&1 \
        || die_env "python3 was not found on PATH"

    local repo_root
    if [[ -n "$ROOT" ]]; then
        [[ -d "$ROOT" ]] || die_env "root is not a directory: $ROOT"
        repo_root="$(cd "$ROOT" && pwd)"
    else
        command -v git >/dev/null 2>&1 || die_env "git was not found on PATH"
        repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" \
            || die_env "not inside a git repository"
    fi
    STEM="${STEM:-default}"

    local stem_dir="$repo_root/.git_auto_review/$STEM"
    local patch="$stem_dir/pre-fix.patch"
    local untracked_tar="$stem_dir/pre-fix.untracked.tar"
    local ignored_manifest="$stem_dir/pre-fix.ignored.manifest"
    [[ -f "$patch" ]] || die_env "pre-fix.patch not found: $patch"
    [[ -f "$untracked_tar" ]] \
        || die_env "pre-fix.untracked.tar not found: $untracked_tar"
    [[ -f "$ignored_manifest" ]] \
        || die_env "pre-fix.ignored.manifest not found: $ignored_manifest"

    local work
    work="$(mktemp -d "${TMPDIR:-/tmp}/git_auto_review.XXXXXX")" \
        || die_env "cannot create a scratch directory"
    local pre="$work/pre"
    local union="$work/union"
    local ignored_now="$work/ignored_now"
    local untracked_pre="$work/untracked_pre"
    local manifest_paths="$work/manifest_paths"
    local dest="$stem_dir/round-r$ROUND.diff.txt"
    mkdir -p "$pre" || { rm -rf "$work"; die_env "cannot create $pre"; }
    : > "$union" || { rm -rf "$work"; die_env "cannot write $union"; }
    : > "$ignored_now" || { rm -rf "$work"; die_env "cannot write $ignored_now"; }
    : > "$untracked_pre" || { rm -rf "$work"; die_env "cannot write $untracked_pre"; }

    build_pre_fix "$repo_root" "$pre" "$patch" "$untracked_tar" \
        || { rm -rf "$work"; die_env "cannot rebuild the round's pre-fix state"; }
    collect_manifest_paths "$ignored_manifest" "$manifest_paths" \
        || { rm -rf "$work"; die_env "cannot read the ignored manifest"; }
    collect_paths "$repo_root" "$union" "$ignored_now" "$untracked_tar" "$untracked_pre" \
        || { rm -rf "$work"; die_env "cannot enumerate the working tree"; }

    local flags_file="$work/membership_flags"
    classify_membership "$union" "$ignored_now" "$manifest_paths" \
        "$untracked_pre" > "$flags_file" \
        || { rm -rf "$work"; die_env "cannot classify the working-tree paths"; }

    : > "$dest" || { rm -rf "$work"; die_env "cannot write $dest"; }

    local path flags in_ignored in_manifest in_untracked pre_exists work_exists
    while IFS= read -r -d '' path \
        && IFS= read -r -d '' flags <&3; do
        is_run_owned_path "$path" && continue
        read -r in_ignored in_manifest in_untracked <<< "$flags"

        if [[ "$in_ignored" == yes && "$in_untracked" == no ]]; then
            # An ignored path the manifest does not hold is the fixer's
            # addition. A pre-existing ignored file stays as the fixer left it.
            [[ "$in_manifest" == yes ]] && continue
            if [[ -e "$repo_root/$path" || -L "$repo_root/$path" ]]; then
                if content_is_binary "$repo_root/$path"; then
                    emit_binary_added "$path" >> "$dest"
                else
                    emit_added "$path" "$repo_root/$path" >> "$dest"
                fi
            fi
            continue
        fi

        pre_exists=no
        [[ -e "$pre/$path" || -L "$pre/$path" ]] && pre_exists=yes
        work_exists=no
        [[ -e "$repo_root/$path" || -L "$repo_root/$path" ]] && work_exists=yes

        if [[ "$pre_exists" == yes && "$work_exists" == yes ]]; then
            cmp -s "$pre/$path" "$repo_root/$path" && continue
            if content_is_binary "$pre/$path" \
                || content_is_binary "$repo_root/$path"; then
                emit_binary_modified "$path" >> "$dest"
            else
                emit_modified "$path" "$pre/$path" "$repo_root/$path" >> "$dest"
            fi
        elif [[ "$work_exists" == yes ]]; then
            if content_is_binary "$repo_root/$path"; then
                emit_binary_added "$path" >> "$dest"
            else
                emit_added "$path" "$repo_root/$path" >> "$dest"
            fi
        elif [[ "$pre_exists" == yes ]]; then
            if content_is_binary "$pre/$path"; then
                emit_binary_removed "$path" >> "$dest"
            else
                emit_removed "$path" "$pre/$path" >> "$dest"
            fi
        fi
    done < "$union" 3< "$flags_file"

    rm -rf "$work"
    printf 'Round diff written at %s\n' "$dest"
    printf '%s\n' "$dest"
}

main "$@"
