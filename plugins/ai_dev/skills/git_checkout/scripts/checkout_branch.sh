#!/usr/bin/env bash
# checkout_branch.sh - branch resolution and checkout helper for /git_checkout.
#
# Bash is required for arrays and [[ ]]; the shebang declares it and main()
# checks git availability before any repository work. `set -e` stays off on
# purpose: this helper classifies its own outcomes into distinct exit codes,
# so every command's status is inspected where it is run.

set -uo pipefail

EXIT_USAGE=1
EXIT_AMBIGUOUS=3
EXIT_MISS=4
EXIT_BLOCKED=5

SUPPORTS_SWITCH=unknown
ARG_REMOTE=""
ARG_BRANCH=""

usage() {
    cat <<'USAGE'
checkout_branch.sh - put the repository onto an existing branch.

Usage:
  checkout_branch.sh <branch>
  checkout_branch.sh <remote>/<branch>
  checkout_branch.sh --help

Behavior:
  - Runs from any path inside a git repository.
  - Fetches every remote without pruning, so a branch pushed since the last
    fetch resolves and no remote-tracking ref is removed as a side effect.
  - Switches to the branch when it already exists locally.
  - Creates a local branch with an explicit upstream when exactly one remote
    carries the name.
  - Holds and asks which remote to track when a bare name resolves on several
    remotes, creating nothing and switching nowhere.
  - Reports the cause when the name resolves nowhere, separating a branch that
    does not exist from one hidden by a narrow fetch refspec.
  - Ends every successful path on a named local branch rather than in detached
    HEAD, including for the <remote>/<branch> argument form.

Exit codes:
  0  the repository is on the requested branch
  1  usage or environment error
  3  a bare name resolves on several remotes; the run asked which to track
  4  the name resolves nowhere; the run reported the cause
  5  git refused the switch because local changes would be overwritten
USAGE
}

die() {
    printf 'git_checkout: %s\n' "$*" >&2
    exit "$EXIT_USAGE"
}

current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'HEAD'
}

# git switch arrived in git 2.23. Detect by version rather than by probing the
# subcommand, so the check stays side-effect free on every host.
git_supports_switch() {
    if [[ "$SUPPORTS_SWITCH" != unknown ]]; then
        [[ "$SUPPORTS_SWITCH" == yes ]]
        return
    fi

    local version major minor
    version="$(git version 2>/dev/null | awk '{print $3}')"
    major="${version%%.*}"
    minor="${version#*.}"
    minor="${minor%%.*}"

    SUPPORTS_SWITCH=no
    case "${major}-${minor}" in
        *[!0-9-]*|-*|*-) ;;
        *)
            if ((major > 2 || (major == 2 && minor >= 23))); then
                SUPPORTS_SWITCH=yes
            fi
            ;;
    esac

    [[ "$SUPPORTS_SWITCH" == yes ]]
}

remote_names() {
    git remote
}

remote_exists() {
    local target="$1" name
    while IFS= read -r name; do
        [[ "$name" == "$target" ]] && return 0
    done < <(remote_names)
    return 1
}

local_branch_exists() {
    git show-ref --verify --quiet "refs/heads/$1"
}

upstream_of() {
    git rev-parse --abbrev-ref --symbolic-full-name "$1@{upstream}" 2>/dev/null
}

# Reduce a remote-qualified argument to its local branch name plus the named
# remote. A bare name, and a slashed name whose first segment is no configured
# remote (`feature/login`), keep every segment as the branch name.
normalize_argument() {
    local raw="$1" head rest

    ARG_REMOTE=""
    ARG_BRANCH="$raw"

    case "$raw" in
        remotes/*) raw="${raw#remotes/}" ;;
    esac

    head="${raw%%/*}"
    rest="${raw#*/}"
    if [[ "$head" != "$raw" && -n "$rest" ]] && remote_exists "$head"; then
        ARG_REMOTE="$head"
        ARG_BRANCH="$rest"
        return 0
    fi

    ARG_BRANCH="$raw"
}

fetch_all() {
    printf 'Fetch: git fetch --all --no-prune (remote-tracking refs left unpruned).\n'
    if ! git fetch --all --no-prune; then
        printf 'Fetch: git fetch --all --no-prune exited non-zero; resolving from the refs already present.\n'
    fi
}

# Enumerate candidates from the refs themselves rather than from a guess, so
# the run knows which case applies before it acts.
remotes_carrying_branch() {
    local branch="$1"
    local refs remote ref

    refs="$(git for-each-ref --format='%(refname:short)' refs/heads refs/remotes)"
    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue
        while IFS= read -r ref; do
            if [[ "$ref" == "$remote/$branch" ]]; then
                printf '%s\n' "$remote"
                break
            fi
        done <<< "$refs"
    done < <(remote_names)
}

# Ask each remote directly whether it advertises the branch, which separates a
# nonexistent branch from one a narrow fetch refspec never maps locally.
remotes_advertising_branch() {
    local branch="$1"
    local remote

    while IFS= read -r remote; do
        [[ -z "$remote" ]] && continue
        if [[ -n "$(git ls-remote --heads "$remote" "refs/heads/$branch" 2>/dev/null)" ]]; then
            printf '%s\n' "$remote"
        fi
    done < <(remote_names)
}

print_refspec() {
    local remote="$1" line
    printf 'Configured fetch refspec for %s:\n' "$remote"
    while IFS= read -r line; do
        [[ -n "$line" ]] && printf '  %s\n' "$line"
    done < <(git config --get-all "remote.$remote.fetch" 2>/dev/null)
}

report_blocking_paths() {
    local output="$1" line found=false

    while IFS= read -r line; do
        case "$line" in
            $'\t'*)
                if [[ "$found" == false ]]; then
                    printf 'Blocking paths:\n'
                    found=true
                fi
                printf '  %s\n' "${line#$'\t'}"
                ;;
        esac
    done <<< "$output"
}

report_switch_blocked() {
    local previous="$1" output="$2"

    printf 'Switch blocked: git refused the switch because local changes would be overwritten.\n'
    printf '%s\n' "$output"
    report_blocking_paths "$output"
    printf 'Kept the worktree exactly as it is; ran no stash, reset, or checkout-discard.\n'
    printf 'Branch still checked out: %s.\n' "$previous"
    printf 'Created nothing and switched nowhere.\n'
}

switch_existing_branch() {
    local branch="$1" previous upstream out rc

    previous="$(current_branch)"
    if [[ "$previous" == "$branch" ]]; then
        printf 'Switch: already on %s.\n' "$branch"
    else
        if git_supports_switch; then
            out="$(git switch --quiet "$branch" 2>&1)" && rc=0 || rc=$?
        else
            out="$(git checkout --quiet "$branch" 2>&1)" && rc=0 || rc=$?
        fi
        if ((rc != 0)); then
            report_switch_blocked "$previous" "$out"
            return "$EXIT_BLOCKED"
        fi
        [[ -n "$out" ]] && printf '%s\n' "$out"
        printf 'Switch: %s -> %s.\n' "$previous" "$branch"
    fi

    printf 'Branch now checked out: %s (already present; no tracking branch created).\n' "$branch"
    upstream="$(upstream_of "$branch")"
    if [[ -n "$upstream" ]]; then
        printf 'Upstream: %s.\n' "$upstream"
    else
        printf 'Upstream: none configured.\n'
    fi
    printf 'Previous branch: %s.\n' "$previous"
}

# Set the upstream explicitly from the resolved remote branch rather than
# relying on git's DWIM, so the result is the same under any push.default or
# DWIM configuration.
create_tracking_branch() {
    local branch="$1" remote="$2" previous out rc

    previous="$(current_branch)"
    if git_supports_switch; then
        out="$(git switch --quiet --create "$branch" --track "$remote/$branch" 2>&1)" && rc=0 || rc=$?
    else
        out="$(git checkout --quiet -b "$branch" --track "$remote/$branch" 2>&1)" && rc=0 || rc=$?
    fi
    if ((rc != 0)); then
        report_switch_blocked "$previous" "$out"
        return "$EXIT_BLOCKED"
    fi
    [[ -n "$out" ]] && printf '%s\n' "$out"

    printf 'Switch: created local branch %s tracking %s/%s.\n' "$branch" "$remote" "$branch"
    printf 'Branch now checked out: %s (created by this run).\n' "$branch"
    printf 'Upstream: %s.\n' "$(upstream_of "$branch")"
    printf 'Previous branch: %s.\n' "$previous"
}

report_ambiguous() {
    local branch="$1"
    shift
    local remote

    printf 'Ambiguous branch name: %s resolves on more than one remote.\n' "$branch"
    printf 'Candidate remote branches:\n'
    for remote in "$@"; do
        printf '  - %s/%s\n' "$remote" "$branch"
    done
    printf 'Question: which remote should the local branch %s track?\n' "$branch"
    printf 'Re-run with the remote-qualified form for the chosen remote, for example: %s/%s\n' "$1" "$branch"
    printf 'Created nothing and switched nowhere.\n'
}

report_miss() {
    local branch="$1" selected_remote="$2"
    local advertising=() other=() remote

    while IFS= read -r remote; do
        [[ -n "$remote" ]] && advertising+=("$remote")
    done < <(remotes_advertising_branch "$branch")

    local advertised_by_selected=false
    if [[ -n "$selected_remote" ]]; then
        printf 'Branch not found on %s: %s carries no branch named %s in this clone.\n' \
            "$selected_remote" "$selected_remote" "$branch"
    elif ((${#advertising[@]} > 0)); then
        printf 'Branch not found locally: %s has no remote-tracking ref in this clone.\n' "$branch"
    else
        printf 'Branch not found: %s exists neither locally nor on any configured remote.\n' "$branch"
    fi

    for remote in ${advertising[@]+"${advertising[@]}"}; do
        if [[ -n "$selected_remote" && "$remote" == "$selected_remote" ]]; then
            advertised_by_selected=true
        elif [[ -n "$selected_remote" ]]; then
            other+=("$remote")
        fi
    done

    if [[ -n "$selected_remote" ]]; then
        if [[ "$advertised_by_selected" == true ]]; then
            printf 'Cause: %s advertises refs/heads/%s, but its fetch refspec never maps that ref into refs/remotes/%s/.\n' \
                "$selected_remote" "$branch" "$selected_remote"
            print_refspec "$selected_remote"
            printf 'Remedy: widen the refspec, for example: git remote set-branches --add %s %s && git fetch %s\n' \
                "$selected_remote" "$branch" "$selected_remote"
        else
            printf 'Cause: %s advertises no refs/heads/%s, so the branch does not exist on that remote.\n' \
                "$selected_remote" "$branch"
        fi
        if ((${#other[@]} > 0)); then
            printf 'Other remotes carrying %s, not used because the remote-qualified argument selects %s alone:\n' \
                "$branch" "$selected_remote"
            for remote in "${other[@]}"; do
                printf '  - %s/%s\n' "$remote" "$branch"
            done
        fi
    elif ((${#advertising[@]} > 0)); then
        printf 'Cause: the branch exists on a remote, but a narrow fetch refspec or single-branch clone never maps it into refs/remotes/.\n'
        for remote in "${advertising[@]}"; do
            printf 'Remote advertising refs/heads/%s: %s\n' "$branch" "$remote"
            print_refspec "$remote"
            printf 'Remedy: widen the refspec, for example: git remote set-branches --add %s %s && git fetch %s\n' \
                "$remote" "$branch" "$remote"
        done
    else
        printf 'Cause: no remote advertises refs/heads/%s, so the branch does not exist.\n' "$branch"
    fi

    printf 'Created nothing and switched nowhere.\n'
}

checkout() {
    local raw="$1"
    local candidates=() remote

    fetch_all

    # A local branch matching the argument verbatim wins before any
    # remote-qualified reading of it, so a local `feature/login` stays intact.
    if local_branch_exists "$raw"; then
        printf 'Resolved: branch %s already exists locally.\n' "$raw"
        switch_existing_branch "$raw"
        return
    fi

    normalize_argument "$raw"
    local branch="$ARG_BRANCH" selected="$ARG_REMOTE"

    if [[ -n "$selected" ]]; then
        printf 'Resolved: argument %s names remote %s and branch %s.\n' "$raw" "$selected" "$branch"
    fi

    if local_branch_exists "$branch"; then
        printf 'Resolved: branch %s already exists locally.\n' "$branch"
        switch_existing_branch "$branch"
        return
    fi

    while IFS= read -r remote; do
        [[ -n "$remote" ]] && candidates+=("$remote")
    done < <(remotes_carrying_branch "$branch")

    if [[ -n "$selected" ]]; then
        for remote in ${candidates[@]+"${candidates[@]}"}; do
            if [[ "$remote" == "$selected" ]]; then
                printf 'Resolved: branch %s found at %s/%s, selected by the remote-qualified argument.\n' \
                    "$branch" "$selected" "$branch"
                create_tracking_branch "$branch" "$selected"
                return
            fi
        done
        report_miss "$branch" "$selected"
        return "$EXIT_MISS"
    fi

    case ${#candidates[@]} in
        0)
            report_miss "$branch" ""
            return "$EXIT_MISS"
            ;;
        1)
            printf 'Resolved: branch %s found at %s/%s only.\n' "$branch" "${candidates[0]}" "$branch"
            create_tracking_branch "$branch" "${candidates[0]}"
            ;;
        *)
            report_ambiguous "$branch" "${candidates[@]}"
            return "$EXIT_AMBIGUOUS"
            ;;
    esac
}

main() {
    local argument repo_root

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        "")
            usage >&2
            die "a branch name is required"
            ;;
        -*)
            die "unknown argument: $1"
            ;;
        *)
            argument="$1"
            shift
            ;;
    esac

    (($# == 0)) || die "one branch name at a time; unexpected extra argument: $1"

    command -v git >/dev/null 2>&1 || die "git was not found on PATH"
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
    cd "$repo_root" || die "could not enter repository root: $repo_root"

    checkout "$argument"
}

main "$@"
