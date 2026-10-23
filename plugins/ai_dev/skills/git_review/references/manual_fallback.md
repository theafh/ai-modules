# git_review - manual fallback

Trigger: `scripts/collect_review_evidence.sh` or
`scripts/extract_heading_range.sh` could not run during the current
`/git_review` run, because the file was missing or the environment refused it.
Re-resolve the script path once and retry before using this fallback. Use only
the section that replaces the step that failed, then return to `SKILL.md` for
the remaining stages.

Every command here reads the repository. None of them stages, commits, moves a
ref, or changes a file in the working tree.

Each block runs as written in bash and in zsh, the default shell on macOS, so
its variable names stay clear of zsh's special parameters such as `status`,
which zsh keeps read-only, and `path`, which zsh ties to `PATH`.

## Fetch Before Any Diff

Goal: put the base and the head at their current remote state before a single
line of diff is read, so a stale local base does not inflate the diff and a
stale local head does not review the wrong code.

```bash
git fetch --all --no-prune
```

## Resolve the Base

Goal: take the base from the pull request when there is one, and otherwise from
the remote's own default branch rather than from a hardcoded name.

```bash
git symbolic-ref --quiet --short refs/remotes/origin/HEAD
git remote show origin | sed -n 's/.*HEAD branch: //p'
```

## Pin the Reviewed Commit

Goal: know which commit the report describes, and leave the user's tree exactly
as it is.

```bash
git rev-parse HEAD
git rev-parse "$HEAD_REF"
git status --porcelain --untracked-files=all
```

The head against its own upstream, which is what the fast-forward decision
rests on. This is a different question from how far the head sits from the base,
so read it separately:

```bash
git rev-parse --abbrev-ref --symbolic-full-name 'topic@{upstream}'
git rev-list --left-right --count 'origin/topic...refs/heads/topic'
```

The first count is how far the local branch is behind its upstream and the
second how far ahead. Behind on a clean tree is the fast-forward case:

```bash
git merge --ff-only origin/topic
```

When the tree is dirty, the local branch has diverged, or a hook refuses the
checkout, review from a detached scratch worktree and remove it when the run
ends:

```bash
WT="$(mktemp -d)/review"
git worktree add --detach "$WT" "$HEAD_REF"
# ... run the file-reading commands inside "$WT" ...
git worktree remove --force "$WT"
```

Run no stash, no reset, and no checkout-discard on the user's tree on any path.

## Collect the Git Layer

Goal: gather the same evidence set the helper writes, one command at a time.

```bash
BASE=origin/main         # the resolved base
HEAD_REF=origin/feature  # the resolved head

git merge-base "$BASE" "$HEAD_REF"
git rev-list --left-right --count "$BASE...$HEAD_REF"
git diff --name-status -M --find-renames "$BASE...$HEAD_REF"
git log --no-merges --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF"
git log --first-parent --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF"
git diff -M --find-renames --no-color --no-ext-diff "$BASE...$HEAD_REF"
git diff --stat --no-color "$BASE...$HEAD_REF"
```

`--no-color` and `--no-ext-diff` keep `color.diff=always` and `diff.external`
from turning the patch into something other than a plain unified diff, so pass
them to every `git diff` here that prints a patch, and `--no-color` to every
`--stat`.

When the whole-range `git diff` fails because one path's content is missing,
diff each changed path on its own for the full diff, the `--stat` output that
fills `diff_stat.txt`, and the removed-hunks view. Take the paths from
`git diff --name-status -z`, which prints each path verbatim, because
`name_status.txt` quotes a non-ASCII name and a quoted name matches no path.
Keep every per-path result that succeeds, and write each path git cannot
produce to `unread_paths.txt` in a scratch directory outside the working tree.
The block prints that file's path last, and the file exists only when a path
was unread. The block starts at the repository's top level, because a pathspec
resolves against the current directory while `name-status` names each path from
the root.

```bash
# per-path retry when the whole-range diff fails
cd "$(git rev-parse --show-toplevel)" || exit
unread_dir=$(mktemp -d)
git diff --name-status -z -M --find-renames "$BASE...$HEAD_REF" |
while IFS= read -r -d '' name_status; do
  IFS= read -r -d '' target_path || break
  case "$name_status" in
    R*|C*) IFS= read -r -d '' target_path || break ;;
  esac
  if git diff -M --find-renames --no-color --no-ext-diff "$BASE...$HEAD_REF" -- "$target_path"; then
    git diff --stat --no-color "$BASE...$HEAD_REF" -- "$target_path"
    git diff -M --no-color --no-ext-diff "$BASE...$HEAD_REF" -- "$target_path" |
      grep -E '^(diff --git |---|\+\+\+|-)'
  else
    printf '%s\n' "$target_path" >> "$unread_dir/unread_paths.txt"
  fi
done
printf 'unread_paths.txt: %s\n' "$unread_dir/unread_paths.txt"
```

The removed-hunks view for the retirement heading when the whole-range diff
succeeds:

```bash
git diff -M --no-color --no-ext-diff "$BASE...$HEAD_REF" | grep -E '^(diff --git |---|\+\+\+|-)'
```

The base-side content of a deleted or renamed path, which the head tree no
longer carries:

```bash
git show "$BASE:path/to/deleted_file"
```

The test merge that answers the structural question:

```bash
git merge-tree --write-tree --name-only "$BASE" "$HEAD_REF"
```

An exit status of 0 means the merge is conflict-free. A non-zero status lists
the conflicting files after the first line.

The credential and home-path scan over the added lines:

Walk the diff with the collector's header window. Treat a line that starts with `---` or `+++` as a header only between a `diff --git` opener and that file's `+++` path header. Take the path from the `+++` header, drop the `b/` prefix, drop a trailing tab, and keep git's quotes when the header is still quoted. Pass `-c core.quotepath=false` so a non-ASCII path stays the name on disk, pass `--src-prefix=a/ --dst-prefix=b/` so that header keeps the `b/` prefix, pass `--no-color --no-ext-diff` so `color.diff=always` and `diff.external` leave a plain unified diff, and pass `--no-textconv` so the line numbers follow the file rather than a conversion driver's output. For `@@` hunk numbering, start at the `+` field inside the opening and closing `@` runs and advance on every context line and every added line. Match the patterns against added content after stripping the leading `+`. Run each pattern once with `grep -anE` over the added-line file and join each matched line number to the path and line file.

The block first changes to the repository's top level, because `git ls-files --others` and a pathspec resolve against the current directory while `git diff` names every path from the root. It scans the range by default. When the whole-range diff fails, it walks the per-path diff of every changed path instead, so the readable paths are still scanned and a path git cannot produce adds nothing. Set `SCAN_MODE=uncommitted` for the working-tree lane. The block then walks the diff from `HEAD`, or from the empty tree on an unborn branch, to the working tree, followed by each untracked file as a new-file diff whose first added line is line 1, closing a file that lacks a final newline the way git closes it. An untracked symlink contributes the path it points to, which is what git records, so the file at the other end is never read. It also walks the staged diff and appends each staged added line that the working-tree walk does not carry for the same path, located at its index line and marked `(staged)`, because the next commit records that line even when the working file has dropped it.

A binary file whose only text view is its textconv driver gets a second walk. For each path that a walked diff shows as binary, the block walks that path's textconv diff and marks each hit `(textconv)` after the line number, because that number counts lines of the converted text. A binary path with no textconv driver adds nothing.

```bash
cd "$(git rev-parse --show-toplevel)" || exit
read -r CREDENTIAL_PATTERN << 'END_CREDENTIAL_PATTERN'
AKIA[0-9A-Z]{16}|ASIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{16,}|github_pat_[A-Za-z0-9_]{20,}|(^|[^A-Za-z0-9_-])sk-[A-Za-z0-9_-]{20,}|sk_live_[A-Za-z0-9]{16,}|xox[baprs]-[A-Za-z0-9-]{10,}|AIza[A-Za-z0-9_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----|(^|[^A-Za-z0-9_-])(([A-Za-z0-9_-]*[_-]key|([A-Za-z0-9_-]*[_-])?KEY)|[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|Key|secret|SECRET|Secret|Token|Password|password|PASSWORD|passwd|PASSWD|token|TOKEN))["']?[[:space:]]*(:=|[:=])[[:space:]]*["'][^$[:space:]][^[:space:]]{7,}|^([[:space:]]*-[[:space:]]+"?|export[[:space:]]+)?(([A-Za-z0-9_-]*[_-]key|([A-Za-z0-9_-]*[_-])?KEY)|[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|Key|secret|SECRET|Secret|Token|Password|password|PASSWORD|passwd|PASSWD|token|TOKEN))=[^$"'[:space:]][^[:space:]]{7,}|(^|[^A-Za-z0-9_-])(([A-Za-z0-9_-]*[_-]key|([A-Za-z0-9_-]*[_-])?KEY)|[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|Key|secret|SECRET|Secret|Token|Password|password|PASSWORD|passwd|PASSWD|token|TOKEN))[[:space:]]*(:=|[:=])[[:space:]]*["'][^"'$][^"']{7,}|^[[:space:]]*(-[[:space:]]+)?(([A-Za-z0-9_-]*[_-]key|([A-Za-z0-9_-]*[_-])?KEY)|[A-Za-z0-9_-]*(api[_-]?key|API[_-]?KEY|Key|secret|SECRET|Secret|Token|Password|password|PASSWORD|passwd|PASSWD|token|TOKEN))[[:space:]]*:[[:space:]]+([[:alnum:]][^][:space:]"'$(){}<>|,;#[]{6,}[0-9!@%^&*+=~][^][:space:]"'$(){}<>|,;#[]*|[[:alnum:]][^][:space:]"'$(){}<>|,;#[]*[0-9!@%^&*+=~][^][:space:]"'$(){}<>|,;#[]{6,}|[0-9][^][:space:]"'$(){}<>|,;#[]{7,})([[:space:]]+#.*)?[[:space:]]*$
END_CREDENTIAL_PATTERN
HOME_PATH_PATTERN='((^|[^A-Za-z0-9._@-])(/home/[A-Za-z0-9._-]+/?|/Users/[A-Za-z0-9._-]+/?)|C:\\\\Users\\\\[A-Za-z0-9._-]+|C:\\Users\\[A-Za-z0-9._-]+)'
fmt=(--src-prefix=a/ --dst-prefix=b/ --no-color --no-ext-diff)
scan_dir=$(mktemp -d)
content="$scan_dir/content"
locs="$scan_dir/locs"
: > "$content"
: > "$locs"
walk_added() {
    awk -v content="$1" -v locs="$2" '
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
            print text > content
            print path ":" lineno > locs
            lineno++
        }
        function advance() {
            if (lineno + 0 == 0) lineno = 1
            lineno++
        }
        /^diff --git / { start_file(); next }
        in_header && /^--- / { next }
        in_header && /^\+\+\+ / { path = b_path($0); in_header = 0; next }
        /^@@/ { in_header = 0; past_hunk = 1; lineno = hunk_start($0); next }
        past_hunk && /^$/ { advance(); next }
        /^\+/ { emit(substr($0, 2)); next }
        /^ / { advance(); next }
    '
}
untracked_diffs() {
    local f
    git -c core.quotepath=false ls-files -z --others --exclude-standard |
        while IFS= read -r -d '' f; do
            printf 'diff --git a/%s b/%s\n--- /dev/null\n+++ b/%s\n' "$f" "$f" "$f"
            if [[ -L "$f" ]]; then
                printf '+%s\n\\ No newline at end of file\n' "$(readlink "$f")"
            elif [[ -f "$f" ]]; then
                sed 's/^/+/' "$f"
                if [[ -s "$f" && $(tail -c 1 "$f" | wc -l) -eq 0 ]]; then
                    printf '\n\\ No newline at end of file\n'
                fi
            fi
        done
}
textconv_diffs() {
    local rec added removed file_path old
    git diff --numstat -z --no-textconv "$@" |
        while IFS= read -r -d '' rec; do
            added=${rec%%$'\t'*}
            rec=${rec#*$'\t'}
            removed=${rec%%$'\t'*}
            file_path=${rec#*$'\t'}
            old=""
            if [[ -z "$file_path" ]]; then
                IFS= read -r -d '' old || break
                IFS= read -r -d '' file_path || break
            fi
            [[ "$added" == "-" && "$removed" == "-" ]] || continue
            git -c core.quotepath=false diff "${fmt[@]}" --textconv "$@" -- ${old:+"$old"} "$file_path"
        done
}
append_textconv() {
    local to_content=$1 to_locs=$2
    shift 2
    : > "$scan_dir/textconv_content"
    : > "$scan_dir/textconv_locs"
    textconv_diffs "$@" | walk_added "$scan_dir/textconv_content" "$scan_dir/textconv_locs"
    cat "$scan_dir/textconv_content" >> "$to_content"
    sed 's/$/ (textconv)/' "$scan_dir/textconv_locs" >> "$to_locs"
}
if [[ "${SCAN_MODE:-range}" == uncommitted ]]; then
    scan_base=$(git rev-parse --verify -q HEAD || git hash-object -t tree /dev/null)
    {
        git -c core.quotepath=false diff "${fmt[@]}" --no-textconv "$scan_base"
        untracked_diffs
    } | walk_added "$content" "$locs"
    append_textconv "$content" "$locs" "$scan_base"
    : > "$scan_dir/index_content"
    : > "$scan_dir/index_locs"
    git -c core.quotepath=false diff --cached "${fmt[@]}" --no-textconv |
        walk_added "$scan_dir/index_content" "$scan_dir/index_locs"
    append_textconv "$scan_dir/index_content" "$scan_dir/index_locs" --cached
    awk -v content="$content" -v locs="$locs" \
        -v icontent="$scan_dir/index_content" -v ilocs="$scan_dir/index_locs" '
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
        }
    '
else
    if git -c core.quotepath=false diff -M --find-renames "${fmt[@]}" --no-textconv \
            "$BASE...$HEAD_REF" > "$scan_dir/diff"; then
        walk_added "$content" "$locs" < "$scan_dir/diff"
    else
        git diff --name-status -z -M --find-renames "$BASE...$HEAD_REF" |
            while IFS= read -r -d '' name_status; do
                IFS= read -r -d '' target_path || break
                case "$name_status" in
                    R*|C*) IFS= read -r -d '' target_path || break ;;
                esac
                git -c core.quotepath=false diff -M --find-renames "${fmt[@]}" --no-textconv \
                    "$BASE...$HEAD_REF" -- "$target_path"
            done | walk_added "$content" "$locs"
    fi
    append_textconv "$content" "$locs" -M --find-renames "$BASE...$HEAD_REF"
fi
join_hits() {
    local label=$1 pattern=$2
    grep -anE "$pattern" "$content" | awk -v label="$label" -v locs="$locs" -v content="$content" '
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
            if (num > 0 && loc[num] != "") printf "%s %s:%s\n", label, loc[num], body[num]
        }
    ' || true
}
join_hits credential "$CREDENTIAL_PATTERN"
join_hits home "$HOME_PATH_PATTERN"
rm -rf "$scan_dir"
```

The diff size and the binary and generated share:

```bash
git diff --stat --no-color "$BASE...$HEAD_REF" | tail -1
git diff --numstat "$BASE...$HEAD_REF" | awk '$1 == "-" { print $3 }'
```

## Review the Uncommitted Lanes

Goal: cover both lanes separately when the repository sits on its default
branch. Run the credential and home-path scan above with
`SCAN_MODE=uncommitted` for the working-tree lane.

```bash
# working-tree lane
cd "$(git rev-parse --show-toplevel)" || exit
git status --porcelain --untracked-files=all
git diff --cached --no-color --no-ext-diff
git diff --no-color --no-ext-diff
git ls-files --others --exclude-standard

# local-commits lane
git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
git log --format='%H%n%an%n%ad%n%B%n---' '@{upstream}..HEAD'
```

## Collect the Forge Layer

Goal: read the discussion and the merge signals when `gh` is installed and
authenticated and the remote is a GitHub repository. When any of that is
missing, review from git alone and name the forge layer as unavailable in the
report lead.

```bash
git config --get-regexp '^remote\..*\.url$'   # the raw URLs, unrewritten
gh auth status
gh pr view --json number,title,body,headRefName,baseRefName,headRefOid,state,mergeable,mergeStateStatus,reviewDecision
gh pr view --json comments
gh pr view --json reviews
gh pr view --json statusCheckRollup
gh api "repos/{owner}/{repo}/rulesets"
```

The inline review threads carry each thread's resolved and outdated state, and
they page on both levels. Page past the first page of the threads and past the
first page of the comments inside each thread, and keep the resolved and the
outdated threads:

```bash
gh api graphql -F owner='{owner}' -F repo='{repo}' -F number=123 -f query='
query($owner:String!,$repo:String!,$number:Int!,$cursor:String){
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
```

A thread whose `comments.pageInfo.hasNextPage` is true carries more replies than
its first page. Page those through the thread's node id, passing each
`endCursor` until `hasNextPage` turns false:

```bash
gh api graphql -f id='<thread-id>' -f cursor='<endCursor>' -f query='
query($id:ID!,$cursor:String){
  node(id:$id){
    ... on PullRequestReviewThread{
      comments(first:100, after:$cursor){
        pageInfo{ hasNextPage endCursor }
        nodes{ author{ login } body createdAt }
      }
    }
  }
}'
```

Report each surface with its count, so an empty discussion is proven rather than
assumed.

## Build the Gate List

Goal: reconcile what the continuous-integration definition runs against what the
project documents as its local entry points, and report a disagreement as its
own finding.

```bash
ls .github/workflows/ 2>/dev/null
test -f Makefile && make help
for f in CLAUDE.md AGENTS.md CONTRIBUTING.md; do test -f "$f" && echo "$f"; done
for f in CHARTER.md ARCHITECTURE.md TESTING.md SECURITY.md; do test -f "$f" && echo "$f"; done
```

A repository carrying none of the guardrail documents is reviewed unchanged and
draws no missing-document finding.

## Extract a Heading Range for a Post

Goal: cut the inclusive slice from the drafted report file, so the headings in
the chat report and in the post stay identical.

```bash
awk '/^## What it retires$/, /^## Decisions the implementer must make before fixing$/' report.md
```

That range ends at the closing heading's own line. To include the section under
the closing heading as well, take the line number of the next heading at the
same level and stop one line before it:

```bash
grep -nE '^#{1,6} ' report.md
sed -n '<from-line>,<to-line>p' report.md
```

## Publish

Goal: post only what the user asked for, under the user's own account, in a form
that stays editable.

```bash
gh pr comment 123 --body-file slice.md
gh pr comment --edit-last --body-file corrected.md
gh pr review 123 --comment --body-file slice.md
gh pr review 123 --approve --body-file approval.md
```

Verify the post through the API and report its URL:

```bash
gh pr view 123 --json comments --jq '.comments[-1].url'
```

Resolve a review thread only when the user asks and the re-review confirmed that
thread's finding closed in the tree:

```bash
gh api graphql -f query='
mutation($thread:ID!){
  resolveReviewThread(input:{threadId:$thread}){ thread{ id isResolved } }
}' -F thread='<thread-id>'
```
