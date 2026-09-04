# git_review - manual fallback

Trigger: `scripts/collect_review_evidence.sh` or
`scripts/extract_heading_range.sh` could not run during the current
`/git_review` run, because the file was missing or the environment refused it.
Re-resolve the script path once and retry before using this fallback. Use only
the section that replaces the step that failed, then return to `SKILL.md` for
the remaining stages.

Every command here reads the repository. None of them stages, commits, moves a
ref, or changes a file in the working tree.

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
git diff --stat "$BASE...$HEAD_REF"
git diff --name-status -M --find-renames "$BASE...$HEAD_REF"
git log --no-merges --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF"
git log --first-parent --format='%H%n%an%n%ad%n%B%n---' "$BASE..$HEAD_REF"
git diff -M --find-renames "$BASE...$HEAD_REF"
```

The removed-hunks view for the retirement heading:

```bash
git diff -M "$BASE...$HEAD_REF" | grep -E '^(diff --git |---|\+\+\+|-)'
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

```bash
git diff "$BASE...$HEAD_REF" | grep -E '^\+' | grep -v '^\+\+\+' |
  grep -nE 'AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|/home/[A-Za-z0-9._-]+/|/Users/[A-Za-z0-9._-]+/'
```

The diff size and the binary and generated share:

```bash
git diff --stat "$BASE...$HEAD_REF" | tail -1
git diff --numstat "$BASE...$HEAD_REF" | awk '$1 == "-" { print $3 }'
```

## Review the Uncommitted Lanes

Goal: cover both lanes separately when the repository sits on its default
branch.

```bash
# working-tree lane
git status --porcelain --untracked-files=all
git diff --cached
git diff
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
