#!/usr/bin/env bash
# refresh_repo.sh - safe repository refresh helper for /git_refresh.

set -euo pipefail

REMOTE="${GIT_REFRESH_REMOTE:-origin}"

usage() {
    cat <<'USAGE'
refresh_repo.sh - refresh a repository's default branch and clean safe branches.

Usage:
  refresh_repo.sh
  refresh_repo.sh --prune-gone [branch ...]
  refresh_repo.sh --force-delete <branch> --confirm-force-delete <branch>

Default behavior:
  - Runs from any path inside a git repository.
  - Fetches from origin with --prune.
  - Resolves the default branch from origin/HEAD, with git remote show as
    fallback.
  - Switches to the default branch when the worktree is clean.
  - Fast-forwards the default branch only when origin can be reached by
    fast-forward.
  - Deletes local branches already merged into the default branch via
    git branch -d.
  - Reports upstream-gone branches for an explicit follow-up action.

Gated behavior:
  --prune-gone deletes upstream-gone branches that have no commits absent from
  the default branch via git branch -d. Branches with unique commits are
  reported and left untouched.

  --force-delete prints the commits that would be lost and deletes the named
  branch via git branch -D only when the matching --confirm-force-delete value
  is present in the same command.
USAGE
}

die() {
    printf 'git_refresh: %s\n' "$*" >&2
    exit 1
}

short_sha() {
    git rev-parse --short "$1" 2>/dev/null || printf '%s' "$1"
}

current_branch() {
    git symbolic-ref --quiet --short HEAD 2>/dev/null || printf 'HEAD'
}

worktree_dirty() {
    [[ -n "$(git status --porcelain)" ]]
}

resolve_default_branch() {
    local remote_ref line branch

    if remote_ref="$(git symbolic-ref --quiet --short "refs/remotes/$REMOTE/HEAD" 2>/dev/null)"; then
        branch="${remote_ref#"${REMOTE}"/}"
        if [[ -n "$branch" && "$branch" != "$remote_ref" ]] &&
            git show-ref --verify --quiet "refs/remotes/$REMOTE/$branch"; then
            printf '%s\n' "$branch"
            return 0
        fi
    fi

    while IFS= read -r line; do
        case "$line" in
            "  HEAD branch: "*)
                branch="${line#  HEAD branch: }"
                if [[ -n "$branch" && "$branch" != "(unknown)" ]]; then
                    printf '%s\n' "$branch"
                    return 0
                fi
                ;;
        esac
    done < <(LC_ALL=C git remote show "$REMOTE" 2>/dev/null)

    return 1
}

fetch_prune() {
    printf 'Fetch/prune: git fetch --prune %s\n' "$REMOTE"
    git fetch --prune "$REMOTE"
}

show_dirty_status() {
    printf 'Dirty worktree: uncommitted changes are present.\n'
    git status --short
}

switch_to_default() {
    local default_branch="$1"
    local before_branch

    before_branch="$(current_branch)"
    if [[ "$before_branch" == "$default_branch" ]]; then
        printf 'Switch: already on default branch %s.\n' "$default_branch"
        return 0
    fi

    if git show-ref --verify --quiet "refs/heads/$default_branch"; then
        if git checkout --quiet "$default_branch"; then
            printf 'Switch: %s -> %s.\n' "$before_branch" "$default_branch"
            return 0
        fi
        printf 'Switch failed: git checkout %s did not complete; skipped fast-forward and branch deletion.\n' \
            "$default_branch"
        return 1
    fi

    if git show-ref --verify --quiet "refs/remotes/$REMOTE/$default_branch"; then
        if git checkout --quiet -b "$default_branch" --track "$REMOTE/$default_branch"; then
            printf 'Switch: created local default branch %s tracking %s/%s.\n' \
                "$default_branch" "$REMOTE" "$default_branch"
            return 0
        fi
        printf 'Switch failed: could not create %s from %s/%s; skipped fast-forward and branch deletion.\n' \
            "$default_branch" "$REMOTE" "$default_branch"
        return 1
    fi

    printf 'Switch skipped: default branch %s was not found locally or at %s/%s.\n' \
        "$default_branch" "$REMOTE" "$default_branch"
    return 1
}

fast_forward_default() {
    local default_branch="$1"
    local upstream before after

    upstream="$(git rev-parse --abbrev-ref --symbolic-full-name "${default_branch}@{upstream}" 2>/dev/null || true)"
    if [[ -z "$upstream" ]] && git show-ref --verify --quiet "refs/remotes/$REMOTE/$default_branch"; then
        upstream="$REMOTE/$default_branch"
    fi
    if [[ -z "$upstream" ]]; then
        printf 'Fast-forward skipped: %s has no upstream.\n' "$default_branch"
        return 0
    fi

    before="$(git rev-parse HEAD)"
    if git merge-base --is-ancestor HEAD "$upstream"; then
        if ! git merge --ff-only --quiet "$upstream"; then
            printf 'Fast-forward failed: git merge --ff-only %s did not complete; %s is unchanged.\n' \
                "$upstream" "$default_branch"
            return 1
        fi
        after="$(git rev-parse HEAD)"
        if [[ "$before" == "$after" ]]; then
            printf 'Fast-forward: %s already up to date at %s.\n' \
                "$default_branch" "$(short_sha "$after")"
        else
            printf 'Fast-forward: %s advanced %s..%s from %s.\n' \
                "$default_branch" "$(short_sha "$before")" "$(short_sha "$after")" "$upstream"
        fi
        return 0
    fi

    if git merge-base --is-ancestor "$upstream" HEAD; then
        printf 'Fast-forward: %s already contains %s; no update needed.\n' \
            "$default_branch" "$upstream"
        return 0
    fi

    printf 'Fast-forward skipped: %s and %s have diverged; no merge or rebase was performed.\n' \
        "$default_branch" "$upstream"
}

delete_cleanly_merged_branches() {
    local default_branch="$1"
    local current branch deleted_any

    current="$(current_branch)"
    deleted_any=false

    while IFS= read -r branch; do
        [[ -z "$branch" ]] && continue
        [[ "$branch" == "$default_branch" ]] && continue
        [[ "$branch" == "$current" ]] && continue

        if git merge-base --is-ancestor "$branch" HEAD; then
            if git branch -d "$branch"; then
                printf 'Deleted merged branch: %s.\n' "$branch"
                deleted_any=true
            else
                printf 'Merged branch retained after git branch -d refused it: %s.\n' "$branch"
            fi
        fi
    done < <(git for-each-ref --format='%(refname:short)' refs/heads)

    if [[ "$deleted_any" == false ]]; then
        printf 'Deleted merged branches: none.\n'
    fi
}

is_gone_branch() {
    local target="$1"
    local branch track

    while IFS=$'\t' read -r branch track; do
        if [[ "$branch" == "$target" && "$track" == "[gone]" ]]; then
            return 0
        fi
    done < <(git for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads)

    return 1
}

list_gone_branches() {
    local default_branch="$1"
    local branch track current commits found

    current="$(current_branch)"
    found=false

    while IFS=$'\t' read -r branch track; do
        [[ -z "$branch" ]] && continue
        [[ "$track" == "[gone]" ]] || continue
        [[ "$branch" == "$default_branch" ]] && continue
        [[ "$branch" == "$current" ]] && continue

        found=true
        commits="$(git log --oneline "refs/heads/${default_branch}..${branch}" 2>/dev/null || true)"
        if [[ -z "$commits" ]]; then
            printf 'safe\t%s\n' "$branch"
        else
            printf 'force\t%s\n%s\n<<git-refresh-commits-end>>\n' "$branch" "$commits"
        fi
    done < <(git for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads)

    [[ "$found" == true ]]
}

print_gated_offer() {
    local default_branch="$1"
    local records line branch commits
    local safe=()
    local force=()

    records="$(list_gone_branches "$default_branch" || true)"
    if [[ -z "$records" ]]; then
        printf 'Gated cleanup: nothing further remains.\n'
        return 0
    fi

    while IFS= read -r line; do
        case "$line" in
            $'safe\t'*)
                branch="${line#*$'\t'}"
                safe+=("$branch")
                ;;
            $'force\t'*)
                branch="${line#*$'\t'}"
                commits=""
                while IFS= read -r line; do
                    [[ "$line" == "<<git-refresh-commits-end>>" ]] && break
                    commits+="${line}"$'\n'
                done
                force+=("${branch}"$'\t'"${commits%$'\n'}")
                ;;
        esac
    done <<< "$records"

    printf 'Follow-up question: handle gated branch cleanup now?\n'
    if ((${#safe[@]} > 0)); then
        printf 'Upstream-gone branches safe to remove after opt-in with git branch -d:\n'
        for branch in "${safe[@]}"; do
            printf '  - %s\n' "$branch"
        done
    fi
    if ((${#force[@]} > 0)); then
        printf 'Branches requiring explicit force-delete confirmation; commits that would be lost:\n'
        for line in "${force[@]}"; do
            branch="${line%%$'\t'*}"
            commits="${line#*$'\t'}"
            printf '  - %s\n' "$branch"
            printf '%s\n' "$commits" | sed 's/^/      /'
        done
    fi
    printf 'Ask to prune gone branches or force-delete named branches to run those gated actions.\n'
}

prepare_default_branch() {
    local default_branch="$1"
    local current

    current="$(current_branch)"
    if worktree_dirty; then
        show_dirty_status
        if [[ "$current" == "$default_branch" ]]; then
            printf 'Skipped fast-forward and branch deletion because the worktree is dirty.\n'
        else
            printf 'Skipped switch to %s, fast-forward, and branch deletion because the worktree is dirty.\n' \
                "$default_branch"
        fi
        return 1
    fi

    if [[ "$current" == "HEAD" ]]; then
        local anchored=false ref
        for ref in "refs/heads/$default_branch" "refs/remotes/$REMOTE/$default_branch"; do
            if git show-ref --verify --quiet "$ref" &&
                git merge-base --is-ancestor HEAD "$ref"; then
                anchored=true
                break
            fi
        done
        if [[ "$anchored" == false ]]; then
            printf 'Skipped switch, fast-forward, and branch deletion: detached HEAD at %s holds commits not on %s.\n' \
                "$(short_sha HEAD)" "$default_branch"
            return 1
        fi
    fi

    switch_to_default "$default_branch" || return 1
    fast_forward_default "$default_branch"
}

default_run() {
    local default_branch

    fetch_prune
    default_branch="$(resolve_default_branch)" || die "could not resolve $REMOTE default branch from remote HEAD"
    printf 'Default branch: %s (from %s/HEAD).\n' "$default_branch" "$REMOTE"

    if prepare_default_branch "$default_branch"; then
        delete_cleanly_merged_branches "$default_branch"
        print_gated_offer "$default_branch"
    fi
}

prune_gone() {
    local targets=("$@")
    local default_branch branch commits deleted_any

    fetch_prune
    default_branch="$(resolve_default_branch)" || die "could not resolve $REMOTE default branch from remote HEAD"
    printf 'Default branch: %s (from %s/HEAD).\n' "$default_branch" "$REMOTE"
    prepare_default_branch "$default_branch" || return 1

    if ((${#targets[@]} == 0)); then
        while IFS= read -r branch; do
            [[ -n "$branch" ]] && targets+=("$branch")
        done < <(
            git for-each-ref --format='%(refname:short)%09%(upstream:track)' refs/heads |
                while IFS=$'\t' read -r branch track; do
                    [[ "$track" == "[gone]" ]] && printf '%s\n' "$branch"
                done
        )
    fi

    deleted_any=false
    for branch in "${targets[@]}"; do
        if [[ "$branch" == "$default_branch" || "$branch" == "$(current_branch)" ]]; then
            printf 'Prune skipped for protected branch: %s.\n' "$branch"
            continue
        fi
        if ! git show-ref --verify --quiet "refs/heads/$branch"; then
            printf 'Prune skipped for missing branch: %s.\n' "$branch"
            continue
        fi
        if ! is_gone_branch "$branch"; then
            printf 'Prune skipped for branch with live upstream or no upstream: %s.\n' "$branch"
            continue
        fi

        commits="$(git log --oneline "refs/heads/${default_branch}..refs/heads/${branch}" 2>/dev/null || true)"
        if [[ -z "$commits" ]]; then
            if git branch -d "$branch"; then
                printf 'Pruned upstream-gone branch with no unique commits: %s.\n' "$branch"
                deleted_any=true
            else
                printf 'Prune kept %s after git branch -d refused it.\n' "$branch"
            fi
        else
            printf 'Force-delete confirmation required for %s; commits that would be lost:\n' "$branch"
            printf '%s\n' "$commits" | sed 's/^/  /'
        fi
    done

    if [[ "$deleted_any" == false ]]; then
        printf 'Pruned upstream-gone branches: none.\n'
    fi
}

force_delete() {
    local branch="$1"
    local confirmation="$2"
    local default_branch commits

    fetch_prune
    default_branch="$(resolve_default_branch)" || die "could not resolve $REMOTE default branch from remote HEAD"
    printf 'Default branch: %s (from %s/HEAD).\n' "$default_branch" "$REMOTE"

    if [[ "$branch" == "$default_branch" || "$branch" == "$(current_branch)" ]]; then
        die "refusing to force-delete protected branch: $branch"
    fi
    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        die "branch not found: $branch"
    fi

    local compare_base="refs/heads/$default_branch"
    if ! git show-ref --verify --quiet "$compare_base"; then
        compare_base="refs/remotes/$REMOTE/$default_branch"
    fi
    commits="$(git log --oneline "${compare_base}..refs/heads/${branch}" 2>/dev/null || true)"
    printf 'Force-delete candidate: %s.\n' "$branch"
    if [[ -n "$commits" ]]; then
        printf 'Commits that would be lost:\n'
        printf '%s\n' "$commits" | sed 's/^/  /'
    else
        printf 'Commits that would be lost: none relative to %s.\n' "$default_branch"
    fi

    if [[ "$confirmation" != "$branch" ]]; then
        die "explicit confirmation required: pass --confirm-force-delete $branch"
    fi

    git branch -D "$branch"
    printf 'Force-deleted branch after explicit confirmation: %s.\n' "$branch"
}

main() {
    local mode="default"
    local force_branch=""
    local force_confirmation=""

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        --prune-gone)
            mode="prune_gone"
            shift
            ;;
        --force-delete)
            mode="force_delete"
            shift
            force_branch="${1:-}"
            [[ -n "$force_branch" ]] || die "--force-delete requires a branch"
            shift
            while (($# > 0)); do
                case "$1" in
                    --confirm-force-delete)
                        shift
                        force_confirmation="${1:-}"
                        [[ -n "$force_confirmation" ]] || die "--confirm-force-delete requires a branch"
                        shift
                        ;;
                    *)
                        die "unknown argument for --force-delete: $1"
                        ;;
                esac
            done
            ;;
        "")
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac

    local repo_root
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
    cd "$repo_root"

    case "$mode" in
        default)
            default_run
            ;;
        prune_gone)
            prune_gone "$@"
            ;;
        force_delete)
            force_delete "$force_branch" "$force_confirmation"
            ;;
    esac
}

main "$@"
